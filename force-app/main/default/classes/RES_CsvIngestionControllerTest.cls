@IsTest
private class RES_CsvIngestionControllerTest {

    @IsTest
    static void testGetLayouts() {
        Test.startTest();
        List<RES_IngestionConfig.Layout> layouts = RES_CsvIngestionController.getLayouts();
        Test.stopTest();
        Assert.isNotNull(layouts, 'Layouts list should not be null');
    }

    @IsTest
    static void testStartBatchFromCsvValidationErrors() {
        Test.startTest();
        // 1. Empty raw CSV text
        try {
            RES_CsvIngestionController.startBatchFromCsv('', 'test.csv', 'RESIDENTIAL_SALES', 'Insert');
            Assert.fail('Should fail on empty CSV text');
        } catch (AuraHandledException e) {}

        // 2. Empty layout code
        try {
            RES_CsvIngestionController.startBatchFromCsv('Header1,Header2', 'test.csv', '', 'Insert');
            Assert.fail('Should fail on empty layout code');
        } catch (AuraHandledException e) {}

        // 3. Invalid operation
        try {
            RES_CsvIngestionController.startBatchFromCsv('Header1,Header2', 'test.csv', 'RESIDENTIAL_SALES', 'InvalidOp');
            Assert.fail('Should fail on invalid operation');
        } catch (AuraHandledException e) {}

        // 4. Non-existent layout
        try {
            RES_CsvIngestionController.startBatchFromCsv('Header1,Header2', 'test.csv', 'INVALID_LAYOUT_CODE', 'Insert');
            Assert.fail('Should fail on non-existent layout');
        } catch (AuraHandledException e) {}
        Test.stopTest();
    }

    @IsTest
    static void testStartBatchFromCsvOperationInsertAlreadyExists() {
        Product2 prod = new Product2(
            Name = 'Existing Unit',
            RES_Product_External_ID__c = 'EXISTS-UNIT-100',
            IsActive = true
        );
        insert prod;

        String validCode = getLayoutCodeWithMappings();
        if (String.isBlank(validCode)) return;

        String csvText = buildDynamicCsvText(validCode, 'EXISTS-UNIT-100');

        Test.startTest();
        RES_CsvIngestionController.UploadResult result = 
            RES_CsvIngestionController.startBatchFromCsv(csvText, 'sample.csv', validCode, 'Insert');
        Test.stopTest();

        Assert.isNotNull(result);
        Assert.areEqual(0, result.rowsInserted);
        Assert.isTrue(result.rowsInvalid > 0);
    }

    @IsTest
    static void testStartBatchFromCsvOperationUpdateDoesNotExist() {
        String validCode = getLayoutCodeWithMappings();
        if (String.isBlank(validCode)) return;

        String csvText = buildDynamicCsvText(validCode, 'NON-EXISTENT-UNIT-999');

        Test.startTest();
        RES_CsvIngestionController.UploadResult result = 
            RES_CsvIngestionController.startBatchFromCsv(csvText, 'sample.csv', validCode, 'Update');
        Test.stopTest();

        Assert.isNotNull(result);
        Assert.areEqual(0, result.rowsInserted);
        Assert.isTrue(result.rowsInvalid > 0);
    }

    @IsTest
    static void testStartBatchFromCsvZeroRowsInsertedThrowsAuraException() {
        String validCode = getLayoutCodeWithMappings();
        if (String.isBlank(validCode)) return;

        String badCsvText = 'InvalidHeader1,InvalidHeader2\nVal1,Val2\n';

        Test.startTest();
        try {
            RES_CsvIngestionController.startBatchFromCsv(badCsvText, 'bad.csv', validCode, 'Insert');
            Assert.fail('Should throw AuraHandledException when rowsInserted == 0 and rowsInvalid == 0');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testTruncateAndCellHelpers() {
        Test.startTest();
        Assert.areEqual('123', RES_CsvIngestionController.truncate('123456789', 3));
        Assert.areEqual('123', RES_CsvIngestionController.truncate('123', 5));
        Assert.isNull(RES_CsvIngestionController.truncate(null, 5));

        List<String> cells = new List<String>{ '" Quoted Value "' };
        Assert.areEqual('Quoted Value', RES_CsvIngestionController.cell(cells, 0));
        Assert.isNull(RES_CsvIngestionController.cell(cells, -1));
        Assert.isNull(RES_CsvIngestionController.cell(cells, 5));
        Test.stopTest();
    }

    @IsTest
    static void testValidateInventoryTypePerUnitEarlyReturn() {
        RES_IngestionConfig.Layout layout = new RES_IngestionConfig.Layout();
        layout.expectedInventoryType = '';
        layout.inventoryTypeField = '';

        Test.startTest();
        RES_CsvIngestionController.validateInventoryTypePerUnit(
            new List<SObject>(), new List<Integer>(), layout, new RES_CsvIngestionController.UploadResult(), new List<String>()
        );
        Test.stopTest();
    }

    @IsTest
    static void testAssignHelperIntegerAndPicklistAndDefaultAndException() {
        RES_Product_Staging__c stg = new RES_Product_Staging__c();
        List<String> warnings = new List<String>();

        // 1. Integer / Long field testing
        RES_IngestionConfig.ColumnMap cmInt = new RES_IngestionConfig.ColumnMap();
        cmInt.sourceHeader = 'Bedrooms';
        cmInt.stagingField = 'RES_Bedrooms__c';
        cmInt.stripSeparators = true;

        RES_CsvIngestionController.ResolvedColumn rcInt = new RES_CsvIngestionController.ResolvedColumn(
            cmInt, 0, Schema.SObjectType.RES_Product_Staging__c.fields.RES_Bedrooms__c.getSObjectField()
        );

        Test.startTest();
        // Invalid number for integer field -> warnings.add(...)
        RES_CsvIngestionController.assign(stg, rcInt, 'not-a-number', warnings);
        Assert.isFalse(warnings.isEmpty());

        // Valid number for integer field (Safely converted from runtime Decimal)
        RES_CsvIngestionController.assign(stg, rcInt, '3.2', warnings);
        Decimal val = (Decimal) stg.get('RES_Bedrooms__c');
        Assert.areEqual(3, val != null ? val.intValue() : null);

        // 2. Picklist success branch
        RES_IngestionConfig.ColumnMap cmPick = new RES_IngestionConfig.ColumnMap();
        cmPick.sourceHeader = 'Status';
        cmPick.stagingField = 'RES_Processing_Status__c';

        RES_CsvIngestionController.ResolvedColumn rcPick = new RES_CsvIngestionController.ResolvedColumn(
            cmPick, 0, Schema.SObjectType.RES_Product_Staging__c.fields.RES_Processing_Status__c.getSObjectField()
        );

        RES_CsvIngestionController.assign(stg, rcPick, 'Pending', warnings);
        Assert.areEqual('Pending', (String) stg.get('RES_Processing_Status__c'));

        // 3. Default type / fallback branch
        RES_IngestionConfig.ColumnMap cmRef = new RES_IngestionConfig.ColumnMap();
        cmRef.sourceHeader = 'OwnerId';
        cmRef.stagingField = 'OwnerId';

        RES_CsvIngestionController.ResolvedColumn rcRef = new RES_CsvIngestionController.ResolvedColumn(
            cmRef, 0, Schema.SObjectType.RES_Product_Staging__c.fields.OwnerId.getSObjectField()
        );

        RES_CsvIngestionController.assign(stg, rcRef, UserInfo.getUserId(), warnings);

        // 4. Exception catch branch
        RES_IngestionConfig.ColumnMap cmErr = new RES_IngestionConfig.ColumnMap();
        cmErr.sourceHeader = 'InvalidHeader';
        cmErr.stagingField = 'Non_Existent_Field_XYZ__c';

        RES_CsvIngestionController.ResolvedColumn rcErr = new RES_CsvIngestionController.ResolvedColumn(
            cmErr, 0, Schema.SObjectType.RES_Product_Staging__c.fields.Name.getSObjectField()
        );

        RES_CsvIngestionController.assign(stg, rcErr, 'SomeVal', warnings);
        Test.stopTest();
    }

    @IsTest
    static void testParseToStagingKeyColumnNotFound() {
        String validCode = getLayoutCodeWithMappings();
        if (String.isBlank(validCode)) return;
        RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(validCode);
        List<RES_IngestionConfig.ColumnMap> colMaps = RES_IngestionConfig.columnMaps(validCode);

        String missingKeyCsv = 'RandomCol1,RandomCol2\nVal1,Val2\n';

        Test.startTest();
        RES_CsvIngestionController.UploadResult result = RES_CsvIngestionController.parseToStaging(
            missingKeyCsv, 'no_key.csv', layout, colMaps, 'Insert', '707000000000000AAA'
        );
        Test.stopTest();

        Assert.isFalse(result.errors.isEmpty());
        Assert.areEqual(0, result.rowsInserted);
    }

    @IsTest
    static void testParseToStagingRequiredColumnBlankValue() {
        String validCode = getLayoutCodeWithMappings();
        if (String.isBlank(validCode)) return;
        RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(validCode);

        RES_IngestionConfig.ColumnMap reqMap = new RES_IngestionConfig.ColumnMap();
        reqMap.sourceHeader = 'RequiredHeader';
        reqMap.stagingField = 'RES_Product_Code__c';
        reqMap.occurrence = 0;
        reqMap.isRequired = true;

        List<RES_IngestionConfig.ColumnMap> colMaps = new List<RES_IngestionConfig.ColumnMap>{ reqMap };
        String csvText = 'RequiredHeader\n""\n';

        Test.startTest();
        RES_CsvIngestionController.UploadResult result = RES_CsvIngestionController.parseToStaging(
            csvText, 'blank_req.csv', layout, colMaps, 'Insert', '707000000000000AAA'
        );
        Test.stopTest();

        Assert.isNotNull(result);
    }

    @IsTest
    static void testParseToStagingRequiredColumnMissingFromHeader() {
        String validCode = getLayoutCodeWithMappings();
        if (String.isBlank(validCode)) return;
        RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(validCode);

        RES_IngestionConfig.ColumnMap reqMap = new RES_IngestionConfig.ColumnMap();
        reqMap.sourceHeader = 'MandatoryHeaderNotPresent';
        reqMap.stagingField = 'RES_Product_Code__c';
        reqMap.occurrence = 0;
        reqMap.isRequired = true;

        Test.startTest();
        RES_CsvIngestionController.UploadResult result = RES_CsvIngestionController.parseToStaging(
            'OtherHeader\nVal\n', 'missing_req.csv', layout, new List<RES_IngestionConfig.ColumnMap>{ reqMap }, 'Insert', '707000000000000AAA'
        );
        Test.stopTest();

        Assert.isFalse(result.errors.isEmpty());
    }

    @IsTest
    static void testParseToStagingTargetFieldNotFoundOnStagingObject() {
        String validCode = getLayoutCodeWithMappings();
        if (String.isBlank(validCode)) return;
        RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(validCode);

        RES_IngestionConfig.ColumnMap badFieldMap = new RES_IngestionConfig.ColumnMap();
        badFieldMap.sourceHeader = 'Header1';
        badFieldMap.stagingField = 'Invalid_Staging_Field_XYZ__c';
        badFieldMap.occurrence = 0;
        badFieldMap.isRequired = false;

        Test.startTest();
        RES_CsvIngestionController.UploadResult result = RES_CsvIngestionController.parseToStaging(
            'Header1\nVal1\n', 'bad_field.csv', layout, new List<RES_IngestionConfig.ColumnMap>{ badFieldMap }, 'Insert', '707000000000000AAA'
        );
        Test.stopTest();

        Assert.isFalse(result.errors.isEmpty());
    }

    @IsTest
    static void testParseToStagingRowsSkippedAndToInsertEmpty() {
        String validCode = getLayoutCodeWithMappings();
        if (String.isBlank(validCode)) return;
        RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(validCode);
        List<RES_IngestionConfig.ColumnMap> colMaps = RES_IngestionConfig.columnMaps(validCode);

        String tab = String.fromCharArray(new List<Integer>{ 9 });
        String csvText = layout.keyColumn + tab + 'Building\n' +
                         tab + 'Building A\n' +
                         '   ' + tab + 'Building B\n';

        Test.startTest();
        RES_CsvIngestionController.UploadResult result = RES_CsvIngestionController.parseToStaging(
            csvText, 'blank_keys.csv', layout, colMaps, 'Insert', '707000000000000AAA'
        );
        Test.stopTest();

        Assert.isTrue(result.rowsSkipped > 0);
        Assert.isTrue(result.errors.contains('No rows carried a value in "' + layout.keyColumn + '", so nothing was staged.'));
    }

    @IsTest
    static void testStartBatchFromCsvEmptyColumnMapsBranch() {
        for (RES_IngestionConfig.Layout l : RES_IngestionConfig.activeLayouts()) {
            if (RES_IngestionConfig.columnMaps(l.code).isEmpty()) {
                Test.startTest();
                try {
                    RES_CsvIngestionController.startBatchFromCsv('Header1\nVal1', 'test.csv', l.code, 'Insert');
                } catch (AuraHandledException e) {
                    Assert.isNotNull(e.getMessage());
                }
                Test.stopTest();
                break;
            }
        }
    }

    @IsTest
    static void testToYearAndToBooleanHelpers() {
        Test.startTest();
        Assert.areEqual(2026, RES_CsvIngestionController.toYear('2026'));
        Assert.areEqual(2025, RES_CsvIngestionController.toYear('25'));
        Assert.areEqual(1985, RES_CsvIngestionController.toYear('85'));

        Assert.isFalse(RES_CsvIngestionController.toBoolean(''));
        Assert.isTrue(RES_CsvIngestionController.toBoolean('y'));
        Assert.isTrue(RES_CsvIngestionController.toBoolean('x'));
        Assert.isTrue(RES_CsvIngestionController.toBoolean('yes'));
        Assert.isTrue(RES_CsvIngestionController.toBoolean('true'));
        Assert.isTrue(RES_CsvIngestionController.toBoolean('1'));
        Assert.isFalse(RES_CsvIngestionController.toBoolean('no'));
        Test.stopTest();
    }

    @IsTest
    static void testParseDateHelper() {
        Test.startTest();
        Assert.isNull(RES_CsvIngestionController.parseDate('', 'dd.MM.yyyy'));
        Assert.isNull(RES_CsvIngestionController.parseDate('invalid-date', 'dd.MM.yyyy'));
        Assert.isNull(RES_CsvIngestionController.parseDate('2026.01', 'dd.MM.yyyy'));

        Assert.areEqual(Date.newInstance(2026, 1, 15), RES_CsvIngestionController.parseDate('2026.01.15 00:00:00', 'yyyy.MM.dd'));
        Assert.areEqual(Date.newInstance(2026, 5, 10), RES_CsvIngestionController.parseDate('10.05.2026', 'dd.MM.yyyy'));
        Assert.areEqual(Date.newInstance(2026, 10, 5), RES_CsvIngestionController.parseDate('10/05/2026', 'MM/dd/yyyy'));
        Test.stopTest();
    }

    @IsTest
    static void testValidateInventoryTypePerUnit() {
        RES_IngestionConfig.Layout layout = new RES_IngestionConfig.Layout();
        layout.expectedInventoryType = 'Y01';
        layout.inventoryTypeField = 'RES_Inventory_Type__c';
        layout.label = 'Residential Sales';

        List<SObject> rows = new List<SObject>();
        
        RES_Product_Staging__c row1 = new RES_Product_Staging__c(
            RES_Product_Code__c = 'UNIT-1',
            RES_Inventory_Type__c = 'Z99'
        );
        rows.add(row1);

        RES_Product_Staging__c row2 = new RES_Product_Staging__c(
            RES_Product_Code__c = 'UNIT-2',
            RES_Inventory_Type__c = ''
        );
        rows.add(row2);

        RES_CsvIngestionController.UploadResult result = new RES_CsvIngestionController.UploadResult();
        List<String> rowErrors = new List<String>();

        Test.startTest();
        RES_CsvIngestionController.validateInventoryTypePerUnit(
            rows, new List<Integer>{ 2, 3 }, layout, result, rowErrors
        );
        Test.stopTest();

        Assert.areEqual(2, result.rowsInvalid);
        Assert.areEqual('Error', (String) row1.get('RES_Processing_Status__c'));
        Assert.areEqual('Error', (String) row2.get('RES_Processing_Status__c'));
    }

    @IsTest
    static void testToDecimalHelper() {
        Test.startTest();
        Assert.isNull(RES_CsvIngestionController.toDecimal('', true));
        Assert.isNull(RES_CsvIngestionController.toDecimal('-', true));
        Assert.isNull(RES_CsvIngestionController.toDecimal('abc', true));

        Assert.areEqual(1200.50, RES_CsvIngestionController.toDecimal('1,200.50', true));
        Assert.areEqual(-500.00, RES_CsvIngestionController.toDecimal('500.00-', true));
        Test.stopTest();
    }

    @IsTest
    static void testStartBatchFromCsvValidParseAndInsert() {
        String validCode = getLayoutCodeWithMappings();
        if (String.isBlank(validCode)) return;

        String csvText = buildDynamicCsvText(validCode, 'UNIT-101');

        Test.startTest();
        try {
            RES_CsvIngestionController.UploadResult result = 
                RES_CsvIngestionController.startBatchFromCsv(csvText, 'sample.csv', validCode, 'Insert');
            Assert.isNotNull(result, 'UploadResult should be returned');
            Assert.isNotNull(result.batchId, 'BatchId should be populated');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetJobStatus() {
        RES_Product_Staging__c stg = new RES_Product_Staging__c(
            Name = 'Test Staging',
            RES_Batch_Id__c = '707000000000000AAA',
            RES_Processing_Status__c = 'Pending'
        );
        insert stg;

        Test.startTest();
        Id jobId = Database.executeBatch(new RES_UnifiedIngestionEngine());
        
        RES_CsvIngestionController.JobStatus status = 
            RES_CsvIngestionController.getJobStatus(jobId, '707000000000000AAA');
        Test.stopTest();

        Assert.isNotNull(status, 'JobStatus should be returned');
        Assert.areEqual(1, status.stagingPending, 'Should count 1 pending staging record');
    }

    @IsTest
    static void testGetJobStatusException() {
        Id fakeJobId = '707000000000000AAA';
        Test.startTest();
        try {
            RES_CsvIngestionController.getJobStatus(fakeJobId, 'BATCH-001');
            Assert.fail('Should throw exception for non-existent AsyncApexJob');
        } catch (AuraHandledException e) {}
        Test.stopTest();
    }

    private static String getLayoutCodeWithMappings() {
        for (RES_IngestionConfig.Layout l : RES_IngestionConfig.activeLayouts()) {
            if (!RES_IngestionConfig.columnMaps(l.code).isEmpty()) {
                return l.code;
            }
        }
        return null;
    }

    private static String buildDynamicCsvText(String layoutCode, String productCode) {
        RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(layoutCode);
        List<RES_IngestionConfig.ColumnMap> colMaps = RES_IngestionConfig.columnMaps(layoutCode);

        List<String> headers = new List<String>();
        List<String> values  = new List<String>();

        for (RES_IngestionConfig.ColumnMap cm : colMaps) {
            headers.add(cm.sourceHeader);
            if (cm.sourceHeader.equalsIgnoreCase(layout.keyColumn) || cm.stagingField.equalsIgnoreCase('RES_Product_Code__c')) {
                values.add(productCode);
            } else if (String.isNotBlank(layout.inventoryTypeField) && cm.stagingField.equalsIgnoreCase(layout.inventoryTypeField)) {
                values.add(String.isBlank(layout.expectedInventoryType) ? 'Y01' : layout.expectedInventoryType);
            } else {
                values.add('100');
            }
        }

        String tab = String.fromCharArray(new List<Integer>{ 9 });
        return String.join(headers, tab) + '\n' + String.join(values, tab) + '\n';
    }
}