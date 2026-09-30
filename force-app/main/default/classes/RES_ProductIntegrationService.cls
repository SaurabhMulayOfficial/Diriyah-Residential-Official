/**
 * @description Synchronizes Product2 (Unit) records with SAP S/4HANA via the Unit_API endpoint.
 *              Builds payload structure following RES_ProductCatalogIntegrationService pattern.
 * @author      Roshan Jambhule
 * @date        2025
 */
public without sharing class RES_ProductIntegrationService extends RES_BaseIntegrationCalloutService {

    @TestVisible private static final Set<String> ROOT_FIELD_SF_NAMES = new Set<String>{
        'Family', 'RES_Business_Entity__c', 'RES_Building__c',
        'AvailabilityDate', 'DiscontinuedDate', 'RES_Floor__c',
        'RES_Area_Type__c', 'RES_Area__c', 'RES_Unit_Status__c',
        'ProductCode', 'Description', 'RES_Profit_Center__c',
        'RES_Type__c'
    };

    @TestVisible private static Set<Id> includedMeasurementIds = new Set<Id>();
    @TestVisible private static Set<Id> fixtureIdsToStamp = new Set<Id>();

    @TestVisible private static final Set<String> FIXTURES_SF_NAMES = new Set<String>{
        'RES_Orientation__c', 'RES_Storeroom__c', 'RES_Elevated__c',
        'RES_Terrace__c', 'RES_Roof_Terrace__c', 'RES_Entry_Courtyard__c',
        'RES_Garage__c', 'RES_Pool__c', 'RES_ID_Finish__c',
        'RES_Drivers_Room__c', 'RES_Maids_Room__c', 'RES_Wadi_View__c',
        'RES_Golf_View__c', 'RES_Panoramic_View__c', 'RES_Private__c',
        'RES_Condition__c', 'RES_Furnished__c'
    };

    /**
     * @description Validates that a populated RES_Product_External_ID__c follows the SAP format
     *              CompanyCode/BusinessEntity/RentalObject (e.g. "1000/140/11002912").
     *              Returns an error message when invalid, null when blank or valid.
     *              Blank is intentionally allowed — it signals a CREATE (Change_Indicator="I").
     */
    @TestVisible
    private static String validateSapExternalIdFormat(String externalId) {
        if (String.isBlank(externalId)) return null;
        Pattern sapIdPat = Pattern.compile('^\\d+/\\d+/\\d+$');
        if (!sapIdPat.matcher(externalId).matches()) {
            return 'RES_Product_External_ID__c "' + externalId
                + '" does not match the SAP identifier format'
                + ' (CompanyCode/BusinessEntity/RentalObject, e.g. "1000/140/11002912").'
                + ' This field must contain only SAP-generated identifiers.'
                + ' Clear the field to trigger an INSERT, or correct it to the exact SAP-provided value.';
        }
        return null;
    }

    /**
     * @description Initializes the service with SAP token and API config for the given HTTP method.
     */
    public RES_ProductIntegrationService(String requestMethod) {
        super();
        List<RES_API_Configuration__mdt> apiConfigList = new RES_APIConfigurationsDAO().getAPIConfiguration(requestMethod, 'Unit_API');

        if (apiConfigList.isEmpty()) {
            throw new RES_IntegrationException('No API configuration found for Product integration with request method: ' + requestMethod);
        }

        setEndpoint(apiConfigList[0].RES_Endpoint__c);

        Integer maxRetries = apiConfigList[0].RES_Max_Retries__c != null ? Integer.valueOf(apiConfigList[0].RES_Max_Retries__c) : 3;
        Integer timeout    = apiConfigList[0].RES_Callout_Timeout__c != null ? Integer.valueOf(apiConfigList[0].RES_Callout_Timeout__c) : 10000;

        String sapToken = new RES_SAPTokenProvider().getToken();
        if (sapToken == null || String.isBlank(sapToken)) {
            throw new RES_IntegrationException('Failed to retrieve SAP token for Product integration.');
        }

        Map<String, String> headers = new Map<String, String>();
        if (apiConfigList[0].RES_Headers__c != null) {
            Map<String, Object> inputHeaders = (Map<String, Object>) JSON.deserializeUntyped(apiConfigList[0].RES_Headers__c);
            for (String key : inputHeaders.keySet()) {
                headers.put(key, String.valueOf(inputHeaders.get(key)));
            }
        }
        headers.put('Authorization', 'Bearer ' + sapToken);

        setHeaders(headers);
        setMaxRetries(maxRetries);
        setRequestMethod(requestMethod);
        setTimeout(timeout);
    }

    /**
     * @description Builds the SAP JSON payload for the given Product2 records.
     */
    public static String hydrateRequestBody(List<Product2> products, String triggerContext) {
        if (products == null || products.isEmpty()) {
            throw new RES_IntegrationException('No Product records provided for integration.');
        }

        Set<Id> productIds = new Set<Id>();
        for (Product2 p : products) {
            if (p.Id != null) productIds.add(p.Id);
        }
        if (productIds.isEmpty()) {
            throw new RES_IntegrationException('No valid Product IDs provided for integration.');
        }

        Set<String> unitSyncFields = new Set<String>();
        RES_SAP_Integration_Config__mdt unitSyncMdt =
            new RES_SAPIntegrationConfigDAO().getSAPIntegrationConfigByDeveloperName('Unit_Sync');
        if (unitSyncMdt != null && String.isNotBlank(unitSyncMdt.RES_Sync_Fields__c)) {
            for (String f : unitSyncMdt.RES_Sync_Fields__c.split(',')) {
                if (String.isNotBlank(f)) unitSyncFields.add(f.trim());
            }
        }

        Map<Id, List<RES_Measurement__c>> measurementsByProduct = new Map<Id, List<RES_Measurement__c>>();
        for (RES_Measurement__c m : new RES_MeasurementDAOLayer().getMeasurementsByProductIds(productIds)) {
            if (!measurementsByProduct.containsKey(m.RES_Product__c)) {
                measurementsByProduct.put(m.RES_Product__c, new List<RES_Measurement__c>());
            }
            measurementsByProduct.get(m.RES_Product__c).add(m);
        }

        RES_SAPValueMappingDAOLayer mappingDAO   = new RES_SAPValueMappingDAOLayer();
        Map<String, String> unitStatusMap       = mappingDAO.getMappingAsMap('Unit_Status');
        Map<String, String> uomCodeMap          = mappingDAO.getMappingAsMap('UOM');
        Map<String, String> inventoryTypeMap    = mappingDAO.getMappingAsMap('Inventory_Type');
        Map<String, String> fixtureBoolTrueMap  = mappingDAO.getMappingAsMap('Fixture_Boolean');
        Map<String, String> fixtureBoolFalseMap    = mappingDAO.getFalseMappingAsMap('Fixture_Boolean');
        Map<String, String> measTypeCustomFieldMap = mappingDAO.getMappingAsMap('Measurement_CustomField');

        includedMeasurementIds.clear();
        fixtureIdsToStamp.clear();
        List<Map<String, Object>> payloads = new List<Map<String, Object>>();

        for (Product2 p : products) {

            // SAP external ID present → UPDATE; blank → CREATE even on afterUpdate (retry scenario)
            String effectiveContext = String.isNotBlank(p.RES_Product_External_ID__c) ? 'U' : 'I';
            if (effectiveContext == 'U') {
                String idFormatErr = validateSapExternalIdFormat(p.RES_Product_External_ID__c);
                if (String.isNotBlank(idFormatErr)) {
                    String fullErr = 'Unit_Sync validation failed for Product ' + p.Id + ': ' + idFormatErr;
                    System.debug('### [Unit_Sync] VALIDATION ERROR: ' + fullErr);
                    RES_IntegrationErrorLogger cfLog = new RES_IntegrationErrorLogger(
                        'Unit_Sync', '', fullErr, null, 'Product2', p.Id, null, 'GET', 'Unit_Sync', 3, 'Client Side'
                    );
                    RES_ResponseWrapper.logError(cfLog);
                    throw new RES_IntegrationException(fullErr);
                }
            }

            Map<String, Object> payload = new Map<String, Object>();
            payload.put('RES_Company_Code',
                p.RES_Business_Entity__r != null ? p.RES_Business_Entity__r.RES_Company_Code__c : null);
            payload.put('Family',              p.Family);
            payload.put('RES_Business_Entity',
                p.RES_Business_Entity__r != null ? p.RES_Business_Entity__r.RES_Business_Entity_Id__c : null);
            payload.put('RES_Building',
                p.RES_Building__r != null ? p.RES_Building__r.RES_Property_Id__c : null);
            // substring(0,10) strips timezone offset that Date.valueOf appends under certain org locale settings
            payload.put('AvailabilityDate',
                p.AvailabilityDate != null
                    ? String.valueOf(p.AvailabilityDate).substring(0, 10) + 'T00:00:00Z'
                    : Datetime.now().format('yyyy-MM-dd') + 'T00:00:00Z');
            payload.put('DiscontinuedDate',
                p.DiscontinuedDate != null
                    ? String.valueOf(p.DiscontinuedDate).substring(0, 10) + 'T00:00:00Z'
                    : '9999-12-31T18:00:00Z');
            // SAP expects 3-digit zero-padded floor code (e.g. "4" → "004")
            String floorCode = p.RES_Floor__c;
            if (String.isNotBlank(floorCode)) {
                try {
                    String padded = String.valueOf(Integer.valueOf(floorCode));
                    while (padded.length() < 3) padded = '0' + padded;
                    floorCode = padded;
                } catch (Exception e) {
                    System.debug('### [Unit_Sync] Non-numeric RES_Floor__c "' + floorCode + '" on Product ' + p.Id + ' — omitting floor field; map to numeric code before syncing.');
                    floorCode = null;
                }
            }
            payload.put('RES_Floor', floorCode);
            payload.put('RES_Area_Type',       p.RES_Area_Type__c);
            payload.put('RES_Area',            p.RES_Area__c);
            String sapStatus = unitStatusMap.containsKey(p.RES_Unit_Status__c)
                ? unitStatusMap.get(p.RES_Unit_Status__c)
                : p.RES_Unit_Status__c;
            payload.put('RES_Unit_Status',     sapStatus);
            payload.put('RES_Profit_Center',   p.RES_Profit_Center__c);
            // Description always flows from ProductCode — SAP enforces a 20-character limit.
            // String.left(n) returns the full value when length ≤ n, so no conditional needed.
            payload.put('Description', String.isNotBlank(p.ProductCode) ? p.ProductCode.left(20) : p.ProductCode);
            payload.put('Change_Indicator',    effectiveContext);
            // INSERT: empty string so SAP registers no existing rental object; UPDATE: last segment of external ID
            String rentalObject = '';
            if (effectiveContext == 'U' && String.isNotBlank(p.RES_Product_External_ID__c)) {
                rentalObject = p.RES_Product_External_ID__c.contains('/')
                    ? p.RES_Product_External_ID__c.substringAfterLast('/')
                    : p.RES_Product_External_ID__c;
            }
            payload.put('RES_Rental_Object', rentalObject);

            List<RES_Measurement__c> measurements = measurementsByProduct.containsKey(p.Id)
                ? measurementsByProduct.get(p.Id) : new List<RES_Measurement__c>();
            List<Map<String, Object>> customFields = buildCustomFields(p, unitSyncFields, inventoryTypeMap, measurements, measTypeCustomFieldMap);
            if (customFields.isEmpty()) {
                String cfErr = 'Unit Sync validation failed for Product ' + p.Id
                    + ': RES_CustomFields must contain at least one populated field.'
                    + ' SAP/MuleSoft rejects payloads with an empty RES_CustomFields array.'
                    + ' Ensure at least one Unit_Sync configured field has a non-blank value on this Product record.';
                System.debug('### [Unit_Sync] VALIDATION ERROR: ' + cfErr);
                RES_IntegrationErrorLogger cfLog = new RES_IntegrationErrorLogger(
                    'Unit_Sync', '', cfErr, null, 'Product2', p.Id, null, 'GET', 'Unit_Sync', 3, 'Client Side'
                );
                RES_ResponseWrapper.logError(cfLog);
                throw new RES_IntegrationException(cfErr);
            }
            payload.put('RES_CustomFields', customFields);

            List<Map<String, Object>> measList = new List<Map<String, Object>>();
            for (RES_Measurement__c m : measurements) {
                String measCI;
                if (effectiveContext == 'I') {
                    measCI = 'I';
                } else if (m.RES_Last_Sync_DateTime__c == null) {
                    measCI = 'I';
                } else if (triggerContext == 'U') {
                    measCI = 'U';
                } else {
                    continue;
                }

                if (String.isBlank(m.RES_Measurement_Type__c)) {
                    System.debug('### [Unit_Sync] Skipping measurement ' + m.Id
                        + ' (' + m.Name + ') — RES_Measurement_Type__c is blank; cannot send to SAP without a type code.');
                    continue;
                }
                if (String.isBlank(m.RES_Unit_Of_Measurement__c)) {
                    System.debug('### [Unit_Sync] Skipping measurement ' + m.Id
                        + ' (' + m.Name + ') — RES_Unit_Of_Measurement__c is blank; SAP requires a UOM.');
                    continue;
                }
                if (m.RES_Measurement_Amount__c == null) {
                    System.debug('### [Unit_Sync] Skipping measurement ' + m.Id
                        + ' (' + m.Name + ') — RES_Measurement_Amount__c is null; SAP requires a numeric amount.');
                    continue;
                }

                Map<String, Object> mMap = new Map<String, Object>();
                mMap.put('Name',                    m.Name);
                mMap.put('RES_Measurement_Type',    m.RES_Measurement_Type__c);
                mMap.put('RES_Measurement_Amount',  m.RES_Measurement_Amount__c);
                mMap.put('RES_Measurement_From',    m.RES_Measurement_From__c != null ? String.valueOf(m.RES_Measurement_From__c) : null);
                mMap.put('RES_Measurement_To',      m.RES_Measurement_To__c   != null ? String.valueOf(m.RES_Measurement_To__c)   : null);
                String uomCode = m.RES_Unit_Of_Measurement__c;
                if (!uomCodeMap.containsKey(uomCode)) {
                    System.debug('### [Unit_Sync] Skipping measurement ' + m.Id
                        + ' (' + m.Name + ') — no SAP UOM mapping found for "'
                        + uomCode + '". Add an entry to RES_SAP_Value_Mapping.UOM MDT.');
                    continue;
                }
                uomCode = uomCodeMap.get(uomCode);
                mMap.put('RES_Unit_Of_Measurement', uomCode);
                mMap.put('Change_Indicator',        measCI);
                measList.add(stripNulls(mMap));
                if (m.Id != null) includedMeasurementIds.add(m.Id);
            }
            if (!measList.isEmpty()) {
                payload.put('RES_Measurements', measList);
            }

            // null DateTime = never synced → INSERT all as "I"; set DateTime = previously synced → UPDATE all as "U"
            String fixtureCtx = p.RES_Fixtures_Last_Sync__c != null ? 'U' : 'I';
            List<Map<String, Object>> fixtures = buildFixturesFittings(p, fixtureCtx, fixtureBoolTrueMap, fixtureBoolFalseMap);
            if (!fixtures.isEmpty()) {
                payload.put('RES_Fixtures_Fittings', fixtures);
                fixtureIdsToStamp.add(p.Id);
            }

            System.debug('### [Unit_Sync] Product: ' + p.Id
                + ' | SAP Rental Object: ' + p.RES_Product_External_ID__c
                + ' | triggerContext: ' + triggerContext
                + ' | effectiveContext: ' + effectiveContext
                + ' | Business Entity: ' + (p.RES_Business_Entity__r != null ? p.RES_Business_Entity__r.RES_Business_Entity_Id__c : 'null')
                + ' | Building: ' + (p.RES_Building__r != null ? p.RES_Building__r.RES_Property_Id__c : 'null')
                + ' | Measurements fetched: ' + measurements.size()
                + ' | Measurements in payload: ' + measList.size()
                + ' | Fixtures/Area included: ' + (effectiveContext == 'I'));

            payloads.add(stripNulls(payload));
        }

        if (payloads.isEmpty()) {
            throw new RES_IntegrationException(
                'Unit Sync aborted: no products produced a valid SAP payload. '
                + 'RES_CustomFields must contain at least one non-blank field. '
                + 'Check that Unit_Sync Custom Metadata fields have values on each Product record.'
            );
        }

        return JSON.serialize(payloads[0], true);
    }

    /**
     * @description Builds the RES_Conditions array from condition mappings, ABA, and PAD records.
     */
    @TestVisible
    private static List<Map<String, Object>> buildConditions(
        List<RES_Condition_Mapping__mdt> condMappings,
        List<AttributeBasedAdjustment> abaList,
        Map<Id, String> ruleSelectorMap,
        List<ProductAttributeDefinition> padList,
        String triggerContext
    ) {
        Map<String, ProductAttributeDefinition> padByName = new Map<String, ProductAttributeDefinition>();
        for (ProductAttributeDefinition pad : padList) {
            if (!padByName.containsKey(pad.Name)) padByName.put(pad.Name, pad);
        }

        List<Map<String, Object>> conditions = new List<Map<String, Object>>();

        for (RES_Condition_Mapping__mdt mapping : condMappings) {
            Map<String, Object> condMap = new Map<String, Object>();
            condMap.put('RES_Condition_Type',     mapping.RES_Condition_Type__c);
            condMap.put('RES_Formula',            mapping.RES_Formula__c);
            condMap.put('RES_Conditions_Purpose', mapping.RES_Conditions_Purpose__c);
            condMap.put('Change_Indicator',       triggerContext);
            if (mapping.RES_Formula__c == 'D') {
                condMap.put('RES_Parameter_1', mapping.RES_Parameter_1__c);
                // RES_Parameter_2 sent as empty string when null — SAP requires the key to be present
                condMap.put('RES_Parameter_2', mapping.RES_Parameter_2__c != null ? mapping.RES_Parameter_2__c : '');
            }

            if (mapping.RES_Handling__c == 'Attribute_Based_Adjustment') {
                for (AttributeBasedAdjustment aba : abaList) {
                    String selector = ruleSelectorMap.get(aba.AttributeBasedAdjRuleId);
                    if (selector == null || selector != mapping.RES_Selector_Value__c) continue;
                    condMap.put('RES_Condition_Price',      aba.AdjustmentValue);
                    condMap.put('RES_Condition_Valid_From', aba.EffectiveFrom != null ? String.valueOf(aba.EffectiveFrom.date()) : null);
                    condMap.put('RES_Condition_Valid_To',   aba.EffectiveTo   != null ? String.valueOf(aba.EffectiveTo.date())   : null);
                    break;
                }
            } else if (mapping.RES_Handling__c == 'Product_Attribute') {
                String attrName = mapping.RES_Attribute_Name__c;
                if (String.isNotBlank(attrName) && padByName.containsKey(attrName)) {
                    ProductAttributeDefinition pad = padByName.get(attrName);
                    if (String.isNotBlank(pad.DefaultValue)) {
                        try {
                            condMap.put('RES_Condition_Price', Decimal.valueOf(pad.DefaultValue));
                        } catch (Exception e) {
                            condMap.put('RES_Condition_Price', pad.DefaultValue);
                        }
                    }
                    condMap.put('RES_Condition_Valid_From', pad.RES_Valid_From__c != null ? String.valueOf(pad.RES_Valid_From__c) : null);
                    condMap.put('RES_Condition_Valid_To',   pad.RES_Valid_To__c   != null ? String.valueOf(pad.RES_Valid_To__c)   : null);
                }
            } else {
                continue;
            }

            Map<String, Object> clean = stripNulls(condMap);
            if (clean.containsKey('RES_Condition_Price')) {
                conditions.add(clean);
            }
        }
        return conditions;
    }

    /**
     * @description Builds the RES_CustomFields array driven by Unit_Sync MDT field list.
     *              Excludes ROOT_FIELD_SF_NAMES and FIXTURES_SF_NAMES; appends address and RES_Type.
     */
    @TestVisible
    private static List<Map<String, Object>> buildCustomFields(
        Product2 p,
        Set<String> mdtFields,
        Map<String, String> inventoryTypeMap,
        List<RES_Measurement__c> measurements,
        Map<String, String> measTypeCustomFieldMap
    ) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        Set<String> addedSapNames = new Set<String>();

        for (String sfField : mdtFields) {
            if (ROOT_FIELD_SF_NAMES.contains(sfField)) continue;
            if (FIXTURES_SF_NAMES.contains(sfField))   continue;

            Object rawVal;
            try {
                rawVal = p.get(sfField);
            } catch (SObjectException e) {
                System.debug('### [Unit_Sync] buildCustomFields: skipping unrecognised field "' + sfField + '"');
                continue;
            }
            if (rawVal == null) continue;

            String sapName = sfField.endsWith('__c') ? sfField.removeEnd('__c') : sfField;
            if (addedSapNames.contains(sapName)) continue;
            String strVal  = formatCustomFieldValue(rawVal);
            if (String.isNotBlank(strVal)) {
                result.add(new Map<String, Object>{ 'name' => sapName, 'value' => strVal });
                addedSapNames.add(sapName);
            }
        }

        // Measurement amounts → CustomFields via Measurement_CustomField SAP value mapping
        if (measurements != null && measTypeCustomFieldMap != null
                && !measurements.isEmpty() && !measTypeCustomFieldMap.isEmpty()) {
            for (RES_Measurement__c m : measurements) {
                if (String.isBlank(m.RES_Measurement_Type__c)) continue;
                String cfName = measTypeCustomFieldMap.get(m.RES_Measurement_Type__c);
                if (String.isBlank(cfName)) continue;
                if (addedSapNames.contains(cfName)) continue;
                if (m.RES_Measurement_Amount__c == null) continue;
                result.add(new Map<String, Object>{ 'name' => cfName, 'value' => String.valueOf(m.RES_Measurement_Amount__c) });
                addedSapNames.add(cfName);
            }
        }

        // RES_Type__c holds SF-internal type values; SAP expects Y01/Z01 derived from RecordType
        if (!addedSapNames.contains('RES_Type') && p.RecordType != null && String.isNotBlank(p.RecordType.DeveloperName)) {
            String rtName = p.RecordType.DeveloperName;
            String invType = inventoryTypeMap.containsKey(rtName)
                ? inventoryTypeMap.get(rtName)
                : (inventoryTypeMap.containsKey('DEFAULT') ? inventoryTypeMap.get('DEFAULT') : 'Z01');
            result.add(new Map<String, Object>{ 'name' => 'RES_Type', 'value' => invType });
            addedSapNames.add('RES_Type');
        }

        String addrJson = buildAddressJson(p);
        if (String.isNotBlank(addrJson)) {
            result.add(new Map<String, Object>{ 'name' => 'RES_Product_Address', 'value' => addrJson });
        }

        return result;
    }

    /** @description Converts a raw SObject field value to a SAP-compatible string (Date → YYYYMMDD). */
    private static String formatCustomFieldValue(Object rawVal) {
        if (rawVal == null) return null;
        if (rawVal instanceof Date)    return String.valueOf((Date) rawVal).replace('-', '');
        if (rawVal instanceof Decimal) return String.valueOf((Decimal) rawVal);
        if (rawVal instanceof Boolean) return String.valueOf((Boolean) rawVal);
        return String.valueOf(rawVal);
    }

    /** @description Serializes compound address fields to a JSON string for the RES_Product_Address custom field. */
    private static String buildAddressJson(Product2 p) {
        Map<String, String> addr = new Map<String, String>();
        if (String.isNotBlank(p.RES_Product_Address__Street__s))     addr.put('street',      p.RES_Product_Address__Street__s);
        if (String.isNotBlank(p.RES_Product_Address__City__s))       addr.put('city',        p.RES_Product_Address__City__s);
        if (String.isNotBlank(p.RES_Product_Address__StateCode__s))  addr.put('state',       p.RES_Product_Address__StateCode__s);
        if (String.isNotBlank(p.RES_Product_Address__PostalCode__s)) addr.put('postalCode',  p.RES_Product_Address__PostalCode__s);
        if (String.isNotBlank(p.RES_Product_Address__CountryCode__s)) addr.put('country',    p.RES_Product_Address__CountryCode__s);
        return addr.isEmpty() ? null : JSON.serialize(addr);
    }

    @TestVisible
    private static List<Map<String, Object>> buildFixturesFittings(
        Product2 p, String triggerContext,
        Map<String, String> boolTrueCodes,
        Map<String, String> boolFalseCodes
    ) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        if (String.isNotBlank(p.RES_Orientation__c))  addChar(result, p.RES_Orientation__c, triggerContext);
        addBoolFixture(result, p.RES_Storeroom__c,       'RES_Storeroom__c',       boolTrueCodes, boolFalseCodes, triggerContext);
        addBoolFixture(result, p.RES_Elevated__c,        'RES_Elevated__c',        boolTrueCodes, boolFalseCodes, triggerContext);
        addBoolFixture(result, p.RES_Terrace__c,         'RES_Terrace__c',         boolTrueCodes, boolFalseCodes, triggerContext);
        addBoolFixture(result, p.RES_Roof_Terrace__c,    'RES_Roof_Terrace__c',    boolTrueCodes, boolFalseCodes, triggerContext);
        addBoolFixture(result, p.RES_Entry_Courtyard__c, 'RES_Entry_Courtyard__c', boolTrueCodes, boolFalseCodes, triggerContext);
        addBoolFixture(result, p.RES_Garage__c,          'RES_Garage__c',          boolTrueCodes, boolFalseCodes, triggerContext);
        addBoolFixture(result, p.RES_Pool__c,            'RES_Pool__c',            boolTrueCodes, boolFalseCodes, triggerContext);
        if (String.isNotBlank(p.RES_ID_Finish__c))    addChar(result, p.RES_ID_Finish__c, triggerContext);
        addBoolFixture(result, p.RES_Drivers_Room__c,    'RES_Drivers_Room__c',    boolTrueCodes, boolFalseCodes, triggerContext);
        addBoolFixture(result, p.RES_Maids_Room__c,      'RES_Maids_Room__c',      boolTrueCodes, boolFalseCodes, triggerContext);
        addBoolFixture(result, p.RES_Wadi_View__c,       'RES_Wadi_View__c',       boolTrueCodes, boolFalseCodes, triggerContext);
        addBoolFixture(result, p.RES_Golf_View__c,       'RES_Golf_View__c',       boolTrueCodes, boolFalseCodes, triggerContext);
        addBoolFixture(result, p.RES_Panoramic_View__c,  'RES_Panoramic_View__c',  boolTrueCodes, boolFalseCodes, triggerContext);
        addBoolFixture(result, p.RES_Private__c,         'RES_Private__c',         boolTrueCodes, boolFalseCodes, triggerContext);
        if (String.isNotBlank(p.RES_Condition__c))    addChar(result, p.RES_Condition__c, triggerContext);
        addBoolFixture(result, p.RES_Furnished__c,       'RES_Furnished__c',       boolTrueCodes, boolFalseCodes, triggerContext);
        return result;
    }

    private static void addBoolFixture(List<Map<String, Object>> r, Boolean val, String sfField,
                                       Map<String, String> boolTrueCodes, Map<String, String> boolFalseCodes, String ctx) {
        String trueCode  = boolTrueCodes.get(sfField);
        String falseCode = boolFalseCodes.get(sfField);
        if (trueCode != null && falseCode != null) addBool(r, val, trueCode, falseCode, ctx);
    }

    private static void addBool(List<Map<String, Object>> r, Boolean val, String trueCode, String falseCode, String ctx) {
        if (val == true) addChar(r, trueCode, ctx);
    }

    private static void addChar(List<Map<String, Object>> r, String code, String ctx) {
        r.add(new Map<String, Object>{
            'RES_Fixtures_Fittings_Characteristics' => code,
            'Change_Indicator' => ctx
        });
    }

    /** @description Processes the SAP response body, logs error items, and returns true on success. */
    @TestVisible
    private static Boolean processResponse(String responseBody, RES_ProductIntegrationService service, Id recordId, String objectType) {
        if (String.isBlank(responseBody)) return false;

        RES_ResponseWrapper responseWrapper = RES_ResponseWrapper.deserialize(responseBody);
        String errorMessage = '';
        Boolean isSuccess   = false;

        if (responseWrapper != null && responseWrapper.responseReturn != null && responseWrapper.responseReturn.item != null) {
            for (RES_ResponseWrapper.ItemWrapper item : responseWrapper.responseReturn.item) {
                if (item.type == 'E' && String.isNotBlank(item.message)) {
                    errorMessage += item.message;
                } else if (item.type == 'S') {
                    isSuccess = true;
                }
            }
        }

        if (String.isNotBlank(errorMessage)) {
            Boolean isReconciliationNeeded = errorMessage.containsIgnoreCase('already exist');
            if (isReconciliationNeeded) {
                System.debug('### [Unit_Sync] RECONCILIATION REQUIRED for ' + recordId
                    + ': SAP reports this rental object already exists but Salesforce has no ExternalId.'
                    + ' Admin must set RES_Product_External_ID__c to the correct SAP identifier.'
                    + ' Full SAP response: ' + responseBody);
            }
            RES_IntegrationErrorLogger log = new RES_IntegrationErrorLogger(
                'Unit_Sync', '', errorMessage,
                JSON.serialize(service.getHeaders()), objectType, recordId,
                String.valueOf(service.getRequestBody()), service.getRequestMethod(),
                'Unit_Sync', service.getRetryCount(),
                isReconciliationNeeded ? 'Reconciliation Required' : 'Client Side'
            );
            RES_ResponseWrapper.logError(log);
        }

        return isSuccess;
    }

    /**
     * @description Validates that measurements of the same type do not have overlapping date ranges.
     *              Returns an error message on conflict, null when valid.
     */
    @TestVisible
    private static String validateMeasurements(List<Map<String, Object>> measList) {
        if (measList == null || measList.isEmpty()) return null;

        Map<String, List<Map<String, Object>>> byType = new Map<String, List<Map<String, Object>>>();
        for (Map<String, Object> m : measList) {
            Object typeObj = m.get('RES_Measurement_Type');
            if (typeObj == null) return 'Measurement is missing RES_Measurement_Type';
            String mType = String.valueOf(typeObj);
            if (!byType.containsKey(mType)) byType.put(mType, new List<Map<String, Object>>());
            byType.get(mType).add(m);
        }

        for (String mType : byType.keySet()) {
            List<Map<String, Object>> typeGroup = byType.get(mType);
            for (Integer i = 0; i < typeGroup.size(); i++) {
                Map<String, Object> a = typeGroup[i];
                Object aFromObj = a.get('RES_Measurement_From');
                Object aToObj   = a.get('RES_Measurement_To');
                if (aFromObj == null || aToObj == null) {
                    return 'Measurement type ' + mType + ': RES_Measurement_From or RES_Measurement_To is missing';
                }
                Date aFrom, aTo;
                try { aFrom = Date.valueOf(String.valueOf(aFromObj)); } catch (Exception e) {
                    return 'Measurement type ' + mType + ': invalid From date "' + aFromObj + '"';
                }
                try { aTo = Date.valueOf(String.valueOf(aToObj)); } catch (Exception e) {
                    return 'Measurement type ' + mType + ': invalid To date "' + aToObj + '"';
                }
                if (aFrom > aTo) {
                    return 'Measurement type ' + mType + ': From (' + aFrom + ') is after To (' + aTo + ')';
                }
                for (Integer j = i + 1; j < typeGroup.size(); j++) {
                    Map<String, Object> b = typeGroup[j];
                    Date bFrom, bTo;
                    try { bFrom = Date.valueOf(String.valueOf(b.get('RES_Measurement_From'))); } catch (Exception e) { continue; }
                    try { bTo   = Date.valueOf(String.valueOf(b.get('RES_Measurement_To')));   } catch (Exception e) { continue; }
                    if (aFrom <= bTo && aTo >= bFrom) {
                        return 'Measurement overlap detected for type ' + mType
                            + ': period [' + aFrom + ' to ' + aTo + ']'
                            + ' overlaps with [' + bFrom + ' to ' + bTo + '].'
                            + ' Correct the date ranges before syncing.';
                    }
                }
            }
        }
        return null;
    }

    /** @description Removes null-valued entries from a map before JSON serialization. */
    private static Map<String, Object> stripNulls(Map<String, Object> m) {
        Map<String, Object> clean = new Map<String, Object>();
        for (String k : m.keySet()) {
            Object v = m.get(k);
            if (v != null) clean.put(k, v);
        }
        return clean;
    }

    /**
     * @description Extracts the SAP rental object number from an INSERT success response.
     *              Parses MessageV4 "RO 1000/140/11002868" and returns "1000/140/11002868".
     */
    private static String extractSAPExternalId(String responseBody) {
        try {
            Map<String, Object> root      = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            Map<String, Object> returnMap = (Map<String, Object>) root.get('Return');
            Object itemObj = returnMap.get('item');
            Map<String, Object> successItem;
            if (itemObj instanceof Map<String, Object>) {
                successItem = (Map<String, Object>) itemObj;
            } else {
                for (Object o : (List<Object>) itemObj) {
                    Map<String, Object> i = (Map<String, Object>) o;
                    if ('S' == String.valueOf(i.get('Type'))) { successItem = i; break; }
                }
            }
            if (successItem == null) return null;
            String msgV4 = String.valueOf(successItem.get('MessageV4'));
            if (String.isNotBlank(msgV4) && msgV4.contains('/')) {
                return msgV4.removeStart('RO ').trim();
            }
        } catch (Exception e) {
            System.debug('extractSAPExternalId error: ' + e.getMessage());
        }
        return null;
    }

    /**
     * @description Sends the Unit sync payload to SAP and stamps sync timestamps on success.
     */
    public static void syncProducts(List<Product2> products, String requestMethod, String triggerContext) {
        if (products == null || products.isEmpty()) return;
        if (products.size() > 1) {
            throw new RES_IntegrationException(
                'Unit_Sync contract violation: syncProducts must be called with exactly 1 Product2 record, '
                + 'but received ' + products.size() + '. Each unit must be an independent integration transaction boundary.'
            );
        }
        RES_ProductIntegrationService service = new RES_ProductIntegrationService(requestMethod);
        String body = hydrateRequestBody(products, triggerContext);
        service.setRequestName('Unit_Sync');
        service.setObjectName('Product2');
        service.setRecordId(String.valueOf(products[0].Id));
        service.setBody(body);

        System.debug('### [Unit_Sync] Final JSON Payload: ' + body);

        try {
            Map<String, Object> parsedBody = (Map<String, Object>) JSON.deserializeUntyped(body);
            Object measObj = parsedBody.get('RES_Measurements');
            if (measObj instanceof List<Object>) {
                List<Map<String, Object>> measForValidation = new List<Map<String, Object>>();
                for (Object o : (List<Object>) measObj) {
                    measForValidation.add((Map<String, Object>) o);
                }
                String validationError = validateMeasurements(measForValidation);
                if (String.isNotBlank(validationError)) {
                    System.debug('### [Unit_Sync] VALIDATION FAILED — SAP callout aborted: ' + validationError);
                    RES_IntegrationErrorLogger errLog = new RES_IntegrationErrorLogger(
                        'Unit_Sync', '', validationError,
                        JSON.serialize(service.getHeaders()), 'Product2', products[0].Id,
                        body, requestMethod, 'Unit_Sync', service.getRetryCount(), 'Client Side'
                    );
                    RES_ResponseWrapper.logError(errLog);
                    return;
                }
            }
        } catch (Exception ve) {
            System.debug('### [Unit_Sync] Measurement validation parse error: ' + ve.getMessage());
        }

        try {
            RES_IntegrationResponse response = service.sendRequest();

            System.debug('### [Unit_Sync] SAP Response | StatusCode: ' + response.statusCode
                + ' | Status: ' + response.status
                + ' | Body: ' + response.responseBody);

            Boolean isSuccess = processResponse(response.responseBody, service, products[0].Id, 'Product2');

            if (isSuccess) {
                String effectiveCtx  = String.isNotBlank(products[0].RES_Product_External_ID__c) ? 'U' : 'I';
                String sapExternalId = effectiveCtx == 'I' ? extractSAPExternalId(response.responseBody) : null;
                List<Product2> toUpdate = new List<Product2>();
                for (Product2 p : products) {
                    Product2 upd = new Product2(Id = p.Id, RES_Last_Sync_DateTime__c = System.now());
                    if (String.isNotBlank(sapExternalId)) {
                        upd.RES_Product_External_ID__c = sapExternalId;
                    }
                    if (fixtureIdsToStamp.contains(p.Id)) {
                        upd.RES_Fixtures_Last_Sync__c = System.now();
                    }
                    toUpdate.add(upd);
                }
                List<Database.SaveResult> results = Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        System.debug('### [Unit_Sync] External ID saved: ' + toUpdate[i].RES_Product_External_ID__c
                            + ' | Product: ' + toUpdate[i].Id);
                    } else {
                        System.debug('### [Unit_Sync] ERROR saving External ID for Product ' + toUpdate[i].Id
                            + ' | Errors: ' + results[i].getErrors());
                    }
                }

                if (!includedMeasurementIds.isEmpty()) {
                    List<RES_Measurement__c> measToStamp = new List<RES_Measurement__c>();
                    for (Id mId : includedMeasurementIds) {
                        measToStamp.add(new RES_Measurement__c(Id = mId, RES_Last_Sync_DateTime__c = System.now()));
                    }
                    List<Database.SaveResult> measResults = Database.update(measToStamp, false, AccessLevel.SYSTEM_MODE);
                    for (Integer i = 0; i < measResults.size(); i++) {
                        if (!measResults[i].isSuccess()) {
                            System.debug('### [Unit_Sync] ERROR stamping Measurement sync time for ' + measToStamp[i].Id
                                + ' | Errors: ' + measResults[i].getErrors());
                        }
                    }
                    System.debug('### [Unit_Sync] Stamped RES_Last_Sync_DateTime__c on ' + measToStamp.size() + ' Measurement(s)');
                }

                // After INSERT success: fire Measurement_Sync events for all related measurements with context 'I'.
                // Suppressed in RES_MeasurementServices while ExternalId was absent; SAP can now link them to the rental object.
                if (String.isNotBlank(sapExternalId)) {
                    List<RES_Measurement__c> relatedMeasurements = [
                        SELECT Id, RES_Category__c, RES_Catalog__c
                        FROM RES_Measurement__c
                        WHERE RES_Product__c = :products[0].Id
                    ];
                    if (!relatedMeasurements.isEmpty()) {
                        Boolean catalogEnabled = new RES_SAPIntegrationConfigDAO()
                            .getSAPIntegrationConfigByDeveloperName('Measurement_Sync_Catalog') != null;
                        List<RES_Integration_Request__e> measEvents = new List<RES_Integration_Request__e>();
                        for (RES_Measurement__c m : relatedMeasurements) {
                            if (m.RES_Category__c != null) {
                                RES_Integration_Request__e req = new RES_Integration_Request__e();
                                req.RES_RecordIds__c = String.valueOf(m.Id);
                                req.RES_Request_Method__c = 'GET';
                                req.RES_Service_Name__c = 'Measurement_Sync';
                                req.RES_Triggering_Context__c = 'I';
                                measEvents.add(req);
                            }
                            if (m.RES_Catalog__c != null && catalogEnabled) {
                                RES_Integration_Request__e catalogReq = new RES_Integration_Request__e();
                                catalogReq.RES_RecordIds__c = String.valueOf(m.Id);
                                catalogReq.RES_Request_Method__c = 'GET';
                                catalogReq.RES_Service_Name__c = 'Measurement_Sync_Catalog';
                                catalogReq.RES_Triggering_Context__c = 'I';
                                measEvents.add(catalogReq);
                            }
                        }
                        if (!measEvents.isEmpty()) {
                            EventBus.publish(measEvents);
                            System.debug('### [Unit_Sync] Published ' + measEvents.size()
                                + ' Measurement_Sync event(s) after INSERT success for Product ' + products[0].Id);
                        }
                    }
                }
            }

        } catch (Exception e) {
            System.debug('Exception occurred while calling the Product Integration Service: ' + e.getMessage());
        }
    }
}