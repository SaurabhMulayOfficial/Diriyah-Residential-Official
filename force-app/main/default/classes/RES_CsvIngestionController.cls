/**
 * Entry point for the Product Inventory Importer tab.
 */
public with sharing class RES_CsvIngestionController {

    private static final String TAB = '\t';
    private static final Integer BATCH_SIZE = 200;
    private static final Integer MAX_REPORTED_ERRORS = 25;

    private static final String STAGING_OBJECT = 'RES_Product_Staging__c';

    private static final String CURLY_APOSTROPHE = String.fromCharArray(new List<Integer>{ 8217 });   // U+2019
    private static final String NBSP             = String.fromCharArray(new List<Integer>{ 160 });    // U+00A0
    private static final String BOM              = String.fromCharArray(new List<Integer>{ 65279 });  // U+FEFF

    private static Map<String, Schema.SObjectField> stagingFieldsCache;

    @AuraEnabled(cacheable=true)
    public static List<RES_IngestionConfig.Layout> getLayouts() {
        return RES_IngestionConfig.activeLayouts();
    }

    @AuraEnabled
    public static UploadResult startBatchFromCsv(String rawCsvText, String fileName, String layoutCode, String operation) {
        if (String.isBlank(rawCsvText)) {
            throw new AuraHandledException('The uploaded file is empty.');
        }
        if (String.isBlank(layoutCode)) {
            throw new AuraHandledException('Select an inventory type before running the import.');
        }
        if (String.isBlank(operation) || !new Set<String>{ 'Insert', 'Update' }.contains(operation)) {
            throw new AuraHandledException('Select whether this upload is an Insert or an Update.');
        }

        RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(layoutCode);
        if (layout == null) {
            throw new AuraHandledException('Inventory type "' + layoutCode + '" is not an active ingestion layout.');
        }

        List<RES_IngestionConfig.ColumnMap> columnMaps = RES_IngestionConfig.columnMaps(layoutCode);
        if (columnMaps.isEmpty()) {
            throw new AuraHandledException(
                'No column mappings are configured for ' + layout.label +
                '. Add RES_Csv_Column_Map__mdt records for this layout before uploading.'
            );
        }

        Id jobId = Database.executeBatch(new RES_UnifiedIngestionEngine(layoutCode), BATCH_SIZE);

        UploadResult result = parseToStaging(rawCsvText, fileName, layout, columnMaps, operation, jobId);
        result.jobId = jobId;

        if (result.rowsInserted == 0) {
            if (result.rowsInvalid > 0) return result;

            String reason = result.errors.isEmpty() ? 'No data rows could be read from the file.' : String.join(result.errors, ' | ');
            throw new AuraHandledException(reason);
        }

        return result;
    }

    @AuraEnabled
    public static JobStatus getJobStatus(Id jobId, String batchId) {
        List<AsyncApexJob> jobs = new RES_AsyncApexJobDAOLayer().getJobById(jobId);
        if (jobs.isEmpty()) {
            throw new AuraHandledException('Batch job ' + jobId + ' was not found.');
        }

        AsyncApexJob job      = jobs[0];
        JobStatus status      = new JobStatus();
        status.status         = job.Status;
        status.itemsProcessed = job.JobItemsProcessed;
        status.totalItems     = job.TotalJobItems;
        status.numberOfErrors = job.NumberOfErrors;
        status.extendedStatus = job.ExtendedStatus;
        status.isComplete     = new Set<String>{ 'Completed', 'Failed', 'Aborted' }.contains(job.Status);

        List<AggregateResult> aggregateResults = new RES_ProductStagingDAOLayer().getStatusCountsByBatchId(batchId);
        for (AggregateResult ar : aggregateResults) {
            String st = (String) ar.get('st');
            Integer c = (Integer) ar.get('c');
            if (st == 'Completed')      status.stagingCompleted = c;
            else if (st == 'Error')   status.stagingErrored   = c;
            else if (st == 'Pending') status.stagingPending   = c;
        }
        return status;
    }

    @TestVisible
    private static UploadResult parseToStaging(
        String csvText,
        String fileName,
        RES_IngestionConfig.Layout layout,
        List<RES_IngestionConfig.ColumnMap> columnMaps,
        String operation,
        Id jobId
    ) {
        UploadResult result = new UploadResult();
        result.fileName     = fileName;
        result.operation    = operation;
        result.layoutCode   = layout.code;
        result.layoutLabel  = layout.label;
        result.batchId      = String.valueOf(jobId);

        List<String> lines = splitLines(csvText);

        Integer headerLineNo = -1;
        for (Integer i = 0; i < lines.size(); i++) {
            if (String.isNotBlank(lines[i])) { headerLineNo = i; break; }
        }
        if (headerLineNo == -1) {
            result.errors.add('The file contains no readable lines.');
            return result;
        }

        String delimiter     = detectDelimiter(lines[headerLineNo]);
        result.delimiterUsed = (delimiter == TAB) ? 'TAB' : delimiter;

        List<String> headerCells = splitLine(lines[headerLineNo], delimiter);
        HeaderIndex hdr          = new HeaderIndex(headerCells);
        result.columnsFound      = hdr.columnCount();

        List<ResolvedColumn> resolved = new List<ResolvedColumn>();
        Map<String, Schema.SObjectField> stagingFields = stagingFields();

        for (RES_IngestionConfig.ColumnMap cm : columnMaps) {
            Schema.SObjectField target = stagingFields.get(cm.stagingField.toLowerCase());
            if (target == null) {
                result.errors.add(
                    'Mapping "' + cm.sourceHeader + '" points at ' + cm.stagingField +
                    ', which does not exist on ' + STAGING_OBJECT + '. Fix the metadata record.'
                );
                continue;
            }

            Integer idx = hdr.indexOf(cm.sourceHeader, cm.occurrence);

            if (idx < 0) {
                String msg = 'Column "' + cm.sourceHeader + '"' +
                             (cm.occurrence > 0 ? ' (occurrence ' + (cm.occurrence + 1) + ')' : '') +
                             ' was not found in the file';
                if (cm.isRequired) {
                    result.errors.add(msg + ' and is required for ' + layout.label + '.');
                } else {
                    result.unmappedColumns.add(cm.sourceHeader);
                }
                continue;
            }
            resolved.add(new ResolvedColumn(cm, idx, target));
        }

        if (!result.errors.isEmpty()) return result;

        Integer keyIndex = hdr.indexOf(layout.keyColumn, 0);
        if (keyIndex < 0) {
            result.errors.add(
                'Key column "' + layout.keyColumn + '" was not found. Detected delimiter: ' +
                result.delimiterUsed + ', columns detected: ' + hdr.columnCount() +
                '. If that looks wrong, the file separator does not match its content.'
            );
            return result;
        }

        Set<String> mappedHeaders = new Set<String>();
        for (ResolvedColumn rc : resolved) mappedHeaders.add(normalizeHeader(rc.config.sourceHeader));
        for (String h : headerCells) {
            String n = normalizeHeader(h);
            if (String.isNotBlank(n) && !mappedHeaders.contains(n)) result.unmappedColumns.add(h.trim());
        }

        List<SObject> toInsert       = new List<SObject>();
        List<Integer> sourceRowOf     = new List<Integer>();
        List<String> rowErrors        = new List<String>();

        for (Integer i = headerLineNo + 1; i < lines.size(); i++) {
            String line = lines[i];
            if (String.isBlank(line)) continue;

            Integer sourceRow  = i + 1;
            List<String> cells = splitLine(line, delimiter);

            if (String.isBlank(cell(cells, keyIndex))) {
                result.rowsSkipped++;
                continue;
            }

            List<String> warnings = new List<String>();
            SObject stg = buildStagingRow(cells, resolved, layout, sourceRow, warnings);
            stg.put('RES_Operation__c', operation);
            stg.put('RES_Batch_Id__c', result.batchId);

            if (!warnings.isEmpty()) {
                stg.put('RES_Error_Log__c',
                    truncate('Row ' + sourceRow + ' parse warnings: ' + String.join(warnings, '; '), 32768));
                for (String w : warnings) {
                    if (rowErrors.size() < MAX_REPORTED_ERRORS) rowErrors.add('Row ' + sourceRow + ': ' + w);
                }
            }
            toInsert.add(stg);
            sourceRowOf.add(sourceRow);
        }

        if (toInsert.isEmpty()) {
            result.errors.add('No rows carried a value in "' + layout.keyColumn + '", so nothing was staged.');
            result.errors.addAll(rowErrors);
            return result;
        }

        validateInventoryTypePerUnit(toInsert, sourceRowOf, layout, result, rowErrors);

        Set<String> codes = new Set<String>();
        for (SObject stg : toInsert) {
            String c = (String) stg.get('RES_Product_Code__c');
            if (String.isNotBlank(c)) codes.add(c);
        }

        Set<String> existing = new Set<String>();
        List<Product2> existingProducts = new RES_Product2DAOLayer().getProductsByExternalIds(codes);
        for (Product2 p : existingProducts) {
            existing.add(p.RES_Product_External_ID__c);
        }

        for (SObject stg : toInsert) {
            if (stg.get('RES_Processing_Status__c') == 'Error') continue;
            String c = (String) stg.get('RES_Product_Code__c');
            String problem;
            if (operation == 'Insert' && existing.contains(c)) {
                problem = 'Unit "' + c + '" already exists. Use the Update operation instead.';
            } else if (operation == 'Update' && !existing.contains(c)) {
                problem = 'Unit "' + c + '" does not exist. Use the Insert operation instead.';
            }
            if (problem != null) {
                stg.put('RES_Processing_Status__c', 'Error');
                stg.put('RES_Error_Log__c', truncate(problem, 32768));
                result.rowsInvalid++;
                if (result.errors.size() < MAX_REPORTED_ERRORS) result.errors.add(problem);
            }
        }

        List<SObject> toStage = new List<SObject>();
        for (SObject stg : toInsert) {
            if (stg.get('RES_Processing_Status__c') == 'Error') continue;
            toStage.add(stg);
        }
        if (toStage.isEmpty()) return result;

        List<Database.SaveResult> saves = Database.insert(toStage, false);
        for (Integer i = 0; i < saves.size(); i++) {
            if (saves[i].isSuccess()) {
                result.rowsInserted++;
            } else {
                result.rowsFailed++;
                if (result.errors.size() < MAX_REPORTED_ERRORS) {
                    result.errors.add(
                        'Staging insert failed for "' + toStage[i].get('RES_Product_Code__c') + '": ' +
                        saves[i].getErrors()[0].getMessage()
                    );
                }
            }
        }
        result.errors.addAll(rowErrors);
        return result;
    }

    private static SObject buildStagingRow(
        List<String> cells,
        List<ResolvedColumn> resolved,
        RES_IngestionConfig.Layout layout,
        Integer sourceRow,
        List<String> warnings
    ) {
        SObject stg = Schema.getGlobalDescribe().get(STAGING_OBJECT).newSObject();

        for (ResolvedColumn rc : resolved) {
            String raw = cell(cells, rc.index);
            if (String.isBlank(raw)) raw = rc.config.defaultValue;
            if (String.isBlank(raw)) {
                if (rc.config.isRequired) {
                    warnings.add(rc.config.sourceHeader + ' is required but empty');
                }
                continue;
            }
            assign(stg, rc, raw, warnings);
        }

        stg.put('RES_Processing_Status__c', 'Pending');

        String code = (String) stg.get('RES_Product_Code__c');
        String cond = (String) stg.get('RES_Condition_Type__c');
        stg.put('Name', truncate(
            (String.isBlank(code) ? 'Row ' + sourceRow : code) + (String.isBlank(cond) ? '' : ' / ' + cond), 80));
        return stg;
    }

    @TestVisible
    private static void assign(SObject stg, ResolvedColumn rc, String raw, List<String> warnings) {
        Schema.DescribeFieldResult dfr = rc.target.getDescribe();
        Schema.DisplayType t           = dfr.getType();
        String header                  = rc.config.sourceHeader;

        try {
            if (t == Schema.DisplayType.STRING || t == Schema.DisplayType.TEXTAREA
                || t == Schema.DisplayType.EMAIL || t == Schema.DisplayType.PHONE
                || t == Schema.DisplayType.URL) {
                Integer len = dfr.getLength();
                stg.put(rc.config.stagingField, len > 0 ? truncate(raw, len) : raw);

            } else if (t == Schema.DisplayType.DOUBLE || t == Schema.DisplayType.CURRENCY
                       || t == Schema.DisplayType.PERCENT) {
                Decimal d = toDecimal(raw, rc.config.stripSeparators);
                if (d == null) { warnings.add(header + ' "' + raw + '" is not a number - left blank'); return; }
                stg.put(rc.config.stagingField, d);

            } else if (t == Schema.DisplayType.INTEGER || t == Schema.DisplayType.LONG) {
                Decimal d = toDecimal(raw, rc.config.stripSeparators);
                if (d == null) { warnings.add(header + ' "' + raw + '" is not a number - left blank'); return; }
                stg.put(rc.config.stagingField, Integer.valueOf(d.setScale(0, System.RoundingMode.HALF_UP)));

            } else if (t == Schema.DisplayType.DATE) {
                Date dt = parseDate(raw, rc.config.dateFormat);
                if (dt == null) { warnings.add(header + ' "' + raw + '" is not a recognised date - left blank'); return; }
                stg.put(rc.config.stagingField, dt);

            } else if (t == Schema.DisplayType.DATETIME) {
                Date dt = parseDate(raw, rc.config.dateFormat);
                if (dt == null) { warnings.add(header + ' "' + raw + '" is not a recognised date - left blank'); return; }
                stg.put(rc.config.stagingField, Datetime.newInstance(dt, Time.newInstance(0, 0, 0, 0)));

            } else if (t == Schema.DisplayType.BOOLEAN) {
                stg.put(rc.config.stagingField, toBoolean(raw));

            } else if (t == Schema.DisplayType.PICKLIST || t == Schema.DisplayType.MULTIPICKLIST) {
                String v = RES_UnifiedIngestionEngine.safePicklist(rc.target, raw);
                if (v == null) {
                    warnings.add(header + ' "' + raw + '" is not an active value on ' + dfr.getName() + ' - left blank');
                    return;
                }
                stg.put(rc.config.stagingField, v);

            } else {
                stg.put(rc.config.stagingField, raw);
            }
        } catch (Exception e) {
            warnings.add(header + ' "' + raw + '" could not be stored in ' + dfr.getName() + ': ' + e.getMessage());
        }
    }

    @TestVisible
    private static void validateInventoryTypePerUnit(
        List<SObject> rows,
        List<Integer> sourceRowOf,
        RES_IngestionConfig.Layout layout,
        UploadResult result,
        List<String> rowErrors
    ) {
        if (String.isBlank(layout.expectedInventoryType) || String.isBlank(layout.inventoryTypeField)) {
            return;
        }
        String expected = layout.expectedInventoryType.trim();

        Set<String> unitsWithExpected = new Set<String>();
        Set<String> allUnits          = new Set<String>();

        for (SObject stg : rows) {
            String code = (String) stg.get('RES_Product_Code__c');
            if (String.isBlank(code)) continue;
            allUnits.add(code);
            Object raw    = stg.get(layout.inventoryTypeField);
            String actual = raw == null ? null : String.valueOf(raw).trim();
            if (String.isNotBlank(actual) && actual.equalsIgnoreCase(expected)) {
                unitsWithExpected.add(code);
            }
        }

        for (Integer i = 0; i < rows.size(); i++) {
            SObject stg   = rows[i];
            String code   = (String) stg.get('RES_Product_Code__c');
            Object raw    = stg.get(layout.inventoryTypeField);
            String actual = raw == null ? null : String.valueOf(raw).trim();

            String problem;
            if (String.isNotBlank(actual) && !actual.equalsIgnoreCase(expected)) {
                problem = 'Inventory Type "' + actual + '" does not belong to ' + layout.label +
                          ', which expects "' + expected + '"';
            } else if (String.isNotBlank(code) && !unitsWithExpected.contains(code)) {
                problem = 'No row for unit "' + code + '" carries Inventory Type "' + expected +
                          '", which ' + layout.label + ' requires';
            }
            if (problem == null) continue;

            stg.put('RES_Processing_Status__c', 'Error');
            stg.put('RES_Error_Log__c', truncate('Row ' + sourceRowOf[i] + ': ' + problem, 32768));
            result.rowsInvalid++;
            if (rowErrors.size() < MAX_REPORTED_ERRORS) {
                rowErrors.add('Row ' + sourceRowOf[i] + ': ' + problem);
            }
        }
    }

    private static Map<String, Schema.SObjectField> stagingFields() {
        if (stagingFieldsCache == null) {
            stagingFieldsCache = Schema.getGlobalDescribe().get(STAGING_OBJECT).getDescribe().fields.getMap();
        }
        return stagingFieldsCache;
    }

    @TestVisible
    private class ResolvedColumn {
        @TestVisible RES_IngestionConfig.ColumnMap config;
        @TestVisible Integer index;
        @TestVisible Schema.SObjectField target;
        @TestVisible ResolvedColumn(RES_IngestionConfig.ColumnMap config, Integer index, Schema.SObjectField target) {
            this.config = config; this.index = index; this.target = target;
        }
    }

    private class HeaderIndex {
        private Map<String, List<Integer>> positions = new Map<String, List<Integer>>();
        private Integer columnCountValue = 0;

        HeaderIndex(List<String> headerCells) {
            this.columnCountValue = headerCells.size();
            for (Integer i = 0; i < headerCells.size(); i++) {
                String key = normalizeHeader(headerCells[i]);
                if (String.isBlank(key)) continue;
                if (!positions.containsKey(key)) positions.put(key, new List<Integer>());
                positions.get(key).add(i);
            }
        }

        Integer columnCount() { return columnCountValue; }

        Integer indexOf(String header, Integer occurrence) {
            List<Integer> idx = positions.get(normalizeHeader(header));
            if (idx == null || occurrence == null || occurrence < 0 || occurrence >= idx.size()) return -1;
            return idx[occurrence];
        }
    }

    private static String detectDelimiter(String headerLine) {
        if (String.isBlank(headerLine)) return ',';
        if (headerLine.contains(TAB)) return TAB;
        if (headerLine.countMatches('|') > 1) return '|';
        if (headerLine.countMatches(';') > headerLine.countMatches(',')) return ';';
        return ',';
    }

    private static List<String> splitLines(String text) {
        return text.replace(BOM, '').replace('\r\n', '\n').replace('\r', '\n').split('\n', -1);
    }

    private static List<String> splitLine(String line, String delimiter) {
        if (line == null) return new List<String>();
        String escaped = (delimiter == '|') ? '\\|' : delimiter;
        return line.split(escaped + '(?=(?:[^"]*"[^"]*")*[^"]*$)', -1);
    }

    private static String normalizeHeader(String header) {
        if (header == null) return '';
        String s = header.replace('"', '')
                         .replace(CURLY_APOSTROPHE, '\'')
                         .replace(NBSP, ' ')
                         .replace(BOM, '')
                         .trim()
                         .toLowerCase();
        return s.replaceAll('\\s+', ' ');
    }

    @TestVisible
    private static String cell(List<String> cells, Integer index) {
        if (index == null || index < 0 || index >= cells.size()) return null;
        String v = cells[index];
        if (v == null) return null;
        v = v.replace(NBSP, ' ').trim();
        if (v.length() >= 2 && v.startsWith('"') && v.endsWith('"')) {
            v = v.substring(1, v.length() - 1).trim();
        }
        return String.isBlank(v) ? null : v;
    }

    @TestVisible
    private static String truncate(String value, Integer maxLength) {
        if (value == null || maxLength == null || value.length() <= maxLength) return value;
        return value.substring(0, maxLength);
    }

    @TestVisible
    private static Decimal toDecimal(String raw, Boolean stripSeparators) {
        if (String.isBlank(raw)) return null;
        String s = raw.trim().replace(' ', '').replace(NBSP, '');
        if (stripSeparators == true) s = s.replace(',', '');
        if (s.endsWith('-')) s = '-' + s.substring(0, s.length() - 1);
        if (s == '-' || s == '.' || String.isBlank(s)) return null;
        try {
            return Decimal.valueOf(s);
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static Date parseDate(String raw, String format) {
        if (String.isBlank(raw)) return null;
        String s = raw.trim();
        if (s.contains(' ')) s = s.substringBefore(' ');

        Boolean monthFirst = String.isNotBlank(format)
                             && format.trim().toLowerCase().startsWith('mm');
        try {
            List<String> p;
            if (s.contains('.'))      p = s.split('\\.');
            else if (s.contains('/')) p = s.split('/');
            else if (s.contains('-')) p = s.split('-');
            else return null;

            if (p.size() != 3) return null;

            if (p[0].length() == 4) {
                return Date.newInstance(Integer.valueOf(p[0]), Integer.valueOf(p[1]), Integer.valueOf(p[2]));
            }
            Integer day   = monthFirst ? Integer.valueOf(p[1]) : Integer.valueOf(p[0]);
            Integer month = monthFirst ? Integer.valueOf(p[0]) : Integer.valueOf(p[1]);
            return Date.newInstance(toYear(p[2]), month, day);
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static Integer toYear(String raw) {
        Integer y = Integer.valueOf(raw.trim());
        if (y < 100) return y < 80 ? 2000 + y : 1900 + y;
        return y;
    }

    @TestVisible
    private static Boolean toBoolean(String raw) {
        if (String.isBlank(raw)) return false;
        String s = raw.trim().toLowerCase();
        return s == 'y' || s == 'x' || s == 'yes' || s == 'true' || s == '1';
    }

    public class UploadResult {
        @AuraEnabled public Id jobId;
        @AuraEnabled public String batchId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String layoutCode;
        @AuraEnabled public String layoutLabel;
        @AuraEnabled public String delimiterUsed;
        @AuraEnabled public Integer columnsFound = 0;
        @AuraEnabled public Integer rowsInserted = 0;
        @AuraEnabled public Integer rowsSkipped  = 0;
        @AuraEnabled public Integer rowsFailed   = 0;
        @AuraEnabled public Integer rowsInvalid  = 0;
        @AuraEnabled public String operation;
        @AuraEnabled public List<String> errors           = new List<String>();
        @AuraEnabled public List<String> unmappedColumns  = new List<String>();
    }

    public class JobStatus {
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isComplete;
        @AuraEnabled public Integer itemsProcessed;
        @AuraEnabled public Integer totalItems;
        @AuraEnabled public Integer numberOfErrors;
        @AuraEnabled public String extendedStatus;
        @AuraEnabled public Integer stagingCompleted = 0;
        @AuraEnabled public Integer stagingErrored   = 0;
        @AuraEnabled public Integer stagingPending   = 0;
    }
}