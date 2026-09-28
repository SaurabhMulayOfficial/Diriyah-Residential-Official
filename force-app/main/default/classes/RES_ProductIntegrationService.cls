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
        'Description', 'RES_Profit_Center__c',
        'RES_Type__c'
    };

    @TestVisible private static Set<Id> includedMeasurementIds = new Set<Id>();

    @TestVisible private static final Set<String> FIXTURES_SF_NAMES = new Set<String>{
        'RES_Orientation__c', 'RES_Storeroom__c', 'RES_Elevated__c',
        'RES_Terrace__c', 'RES_Roof_Terrace__c', 'RES_Entry_Courtyard__c',
        'RES_Garage__c', 'RES_Pool__c', 'RES_ID_Finish__c',
        'RES_Drivers_Room__c', 'RES_Maids_Room__c', 'RES_Wadi_View__c',
        'RES_Golf_View__c', 'RES_Panoramic_View__c', 'RES_Private__c',
        'RES_Condition__c', 'RES_Furnished__c'
    };

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

        List<AttributeBasedAdjustment> allAba = new RES_AttributeBasedAdjustmentDAOLayer().getByProductIds(productIds);
        Set<Id> ruleIds = new Set<Id>();
        for (AttributeBasedAdjustment aba : allAba) {
            if (aba.AttributeBasedAdjRuleId != null) ruleIds.add(aba.AttributeBasedAdjRuleId);
        }
        Map<Id, String> ruleSelectorMap = new Map<Id, String>();
        if (!ruleIds.isEmpty()) {
            for (AttributeAdjustmentCondition aac : new RES_AttributeAdjustmentConditionDAOLayer().getConditionsByRuleIds(ruleIds)) {
                if (String.isNotBlank(aac.StringValue)) {
                    ruleSelectorMap.put(aac.AttributeBasedAdjRuleId, aac.StringValue);
                }
            }
        }
        Map<Id, List<AttributeBasedAdjustment>> abaByProduct = new Map<Id, List<AttributeBasedAdjustment>>();
        for (AttributeBasedAdjustment aba : allAba) {
            if (aba.ProductId == null) continue;
            if (!abaByProduct.containsKey(aba.ProductId)) {
                abaByProduct.put(aba.ProductId, new List<AttributeBasedAdjustment>());
            }
            abaByProduct.get(aba.ProductId).add(aba);
        }

        Map<Id, List<ProductAttributeDefinition>> padByProduct = new Map<Id, List<ProductAttributeDefinition>>();
        for (ProductAttributeDefinition pad : new RES_ProductAttributeDefinitionDAOLayer().getByProductIds(productIds)) {
            if (!padByProduct.containsKey(pad.Product2Id)) {
                padByProduct.put(pad.Product2Id, new List<ProductAttributeDefinition>());
            }
            padByProduct.get(pad.Product2Id).add(pad);
        }

        Map<String, List<RES_Condition_Mapping__mdt>> condMappingsByLayout = new Map<String, List<RES_Condition_Mapping__mdt>>();
        Map<String, String> rtToLayoutCode = new Map<String, String>();
        for (RES_Ingestion_Layout__mdt layout : new RES_IngestionLayoutDAOLayer().getActiveLayouts()) {
            if (String.isNotBlank(layout.RES_Product_Record_Type__c) && String.isNotBlank(layout.RES_Layout_Code__c)) {
                rtToLayoutCode.put(layout.RES_Product_Record_Type__c, layout.RES_Layout_Code__c);
            }
        }

        Map<String, String> unitStatusMap = new Map<String, String>{
            'Available'                => 'Z10',
            'Sold'                     => 'Z11',
            'Soft Hold'                => 'Z03',
            'Hard Block'               => 'Z06',
            'Draft'                    => 'Z01',
            'Pending DevCo Approval'   => 'Z01',
            'Pending Finance Approval' => 'Z01',
            'Pending CSO Approval'     => 'Z01',
            'Rejected'                 => 'Z05'
        };

        Map<String, String> uomCodeMap = new Map<String, String>{
            'Sqr Mtr' => 'M2',
            'Pcs'     => 'PC'
        };

        includedMeasurementIds.clear();
        List<Map<String, Object>> payloads = new List<Map<String, Object>>();

        for (Product2 p : products) {

            // SAP external ID present → UPDATE; blank → CREATE even on afterUpdate (retry scenario)
            String effectiveContext = String.isNotBlank(p.RES_Product_External_ID__c) ? 'U' : 'I';

            Map<String, Object> payload = new Map<String, Object>();
            payload.put('RES_Company_Code',
                p.RES_Business_Entity__r != null ? p.RES_Business_Entity__r.RES_Company_Code__c : null);
            payload.put('Family',              p.Family);
            payload.put('RES_Business_Entity',
                p.RES_Business_Entity__r != null ? p.RES_Business_Entity__r.RES_Business_Entity_Id__c : null);
            payload.put('RES_Building',
                p.RES_Building__r != null ? p.RES_Building__r.RES_Property_Id__c : null);
            // substring(0,10) strips timezone offset that Date.valueOf appends under certain org locale settings
            payload.put('AvailabilityDate',    p.AvailabilityDate  != null ? String.valueOf(p.AvailabilityDate).substring(0, 10)  + 'T00:00:00Z' : null);
            payload.put('DiscontinuedDate',    p.DiscontinuedDate  != null ? String.valueOf(p.DiscontinuedDate).substring(0, 10)  + 'T00:00:00Z' : null);
            // SAP expects 3-digit zero-padded floor code (e.g. "4" → "004")
            String floorCode = p.RES_Floor__c;
            if (String.isNotBlank(floorCode)) {
                try {
                    String padded = String.valueOf(Integer.valueOf(floorCode));
                    while (padded.length() < 3) padded = '0' + padded;
                    floorCode = padded;
                } catch (Exception e) { /* non-numeric floor value — send as-is */ }
            }
            payload.put('RES_Floor', floorCode);
            payload.put('RES_Area_Type',       p.RES_Area_Type__c);
            payload.put('RES_Area',            p.RES_Area__c);
            String sapStatus = unitStatusMap.containsKey(p.RES_Unit_Status__c)
                ? unitStatusMap.get(p.RES_Unit_Status__c)
                : p.RES_Unit_Status__c;
            payload.put('RES_Unit_Status',     sapStatus);
            payload.put('RES_Profit_Center',   p.RES_Profit_Center__c);
            payload.put('Description',         p.Description);
            payload.put('Change_Indicator',    effectiveContext);
            // INSERT: empty string so SAP registers no existing rental object; UPDATE: last segment of external ID
            String rentalObject = '';
            if (effectiveContext == 'U' && String.isNotBlank(p.RES_Product_External_ID__c)) {
                rentalObject = p.RES_Product_External_ID__c.contains('/')
                    ? p.RES_Product_External_ID__c.substringAfterLast('/')
                    : p.RES_Product_External_ID__c;
            }
            payload.put('RES_Rental_Object', rentalObject);

            List<Map<String, Object>> customFields = buildCustomFields(p, unitSyncFields);
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

            List<RES_Measurement__c> measurements = measurementsByProduct.containsKey(p.Id)
                ? measurementsByProduct.get(p.Id) : new List<RES_Measurement__c>();
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

                Map<String, Object> mMap = new Map<String, Object>();
                mMap.put('Name',                    m.Name);
                mMap.put('RES_Measurement_Type',    m.RES_Measurement_Type__c);
                mMap.put('RES_Measurement_Amount',  m.RES_Measurement_Amount__c);
                mMap.put('RES_Measurement_From',    m.RES_Measurement_From__c != null ? String.valueOf(m.RES_Measurement_From__c) : null);
                mMap.put('RES_Measurement_To',      m.RES_Measurement_To__c   != null ? String.valueOf(m.RES_Measurement_To__c)   : null);
                String uomCode = m.RES_Unit_Of_Measurement__c;
                if (String.isNotBlank(uomCode) && uomCodeMap.containsKey(uomCode)) {
                    uomCode = uomCodeMap.get(uomCode);
                }
                mMap.put('RES_Unit_Of_Measurement', uomCode);
                mMap.put('Change_Indicator',        measCI);
                measList.add(stripNulls(mMap));
                if (m.Id != null) includedMeasurementIds.add(m.Id);
            }
            if (!measList.isEmpty()) {
                payload.put('RES_Measurements', measList);
            }

            String rtName     = p.RecordType != null ? p.RecordType.DeveloperName : null;
            String layoutCode = rtToLayoutCode.containsKey(rtName) ? rtToLayoutCode.get(rtName) : null;
            if (String.isNotBlank(layoutCode) && !condMappingsByLayout.containsKey(layoutCode)) {
                condMappingsByLayout.put(layoutCode, new RES_ConditionMappingDAOLayer().getActiveConditionMappingsByLayoutCode(layoutCode));
            }
            List<RES_Condition_Mapping__mdt> condMappings = String.isNotBlank(layoutCode) && condMappingsByLayout.containsKey(layoutCode)
                ? condMappingsByLayout.get(layoutCode) : new List<RES_Condition_Mapping__mdt>();
            List<AttributeBasedAdjustment> productAba = abaByProduct.containsKey(p.Id)
                ? abaByProduct.get(p.Id) : new List<AttributeBasedAdjustment>();
            List<ProductAttributeDefinition> productPad = padByProduct.containsKey(p.Id)
                ? padByProduct.get(p.Id) : new List<ProductAttributeDefinition>();
            List<Map<String, Object>> conditions = buildConditions(condMappings, productAba, ruleSelectorMap, productPad, effectiveContext);
            if (!conditions.isEmpty()) {
                payload.put('RES_Conditions', conditions);
            }

            // Fixtures sent on INSERT only; SAP rejects re-send on UPDATE (duplicate-key error)
            if (effectiveContext == 'I') {
                List<Map<String, Object>> fixtures = buildFixturesFittings(p, effectiveContext);
                if (!fixtures.isEmpty()) {
                    payload.put('RES_Fixtures_Fittings', fixtures);
                }
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

        return payloads.size() == 1 ? JSON.serialize(payloads[0], true) : JSON.serialize(payloads, true);
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
    private static List<Map<String, Object>> buildCustomFields(Product2 p, Set<String> mdtFields) {
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

        // RES_Type__c holds SF-internal type values; SAP expects Y01/Z01 derived from RecordType
        if (!addedSapNames.contains('RES_Type') && p.RecordType != null && String.isNotBlank(p.RecordType.DeveloperName)) {
            String invType = p.RecordType.DeveloperName == 'RES_Residential_Sales' ? 'Y01' : 'Z01';
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

    private static final Map<String, String> COUNTRY_CODE_NAMES = new Map<String, String>{
        'SA' => 'Saudi Arabia'
    };
    private static final Map<String, String> SA_STATE_CODE_NAMES = new Map<String, String>{
        '01' => 'Riyadh Region',    '02' => 'Makkah Region',           '03' => 'Madinah Region',
        '04' => 'Eastern Region',   '05' => 'Qassim Region',           '06' => 'Hail Region',
        '07' => 'Tabuk Region',     '08' => 'Northern Borders Region', '09' => 'Jizan Region',
        '10' => 'Najran Region',    '11' => 'Al Bahah Region',         '12' => 'Al Jawf Region',
        '13' => 'Asir Region'
    };

    /** @description Serializes compound address fields to a JSON string for the RES_Product_Address custom field. */
    private static String buildAddressJson(Product2 p) {
        Map<String, String> addr = new Map<String, String>();
        if (String.isNotBlank(p.RES_Product_Address__Street__s))     addr.put('street',     p.RES_Product_Address__Street__s);
        if (String.isNotBlank(p.RES_Product_Address__City__s))       addr.put('city',       p.RES_Product_Address__City__s);
        if (String.isNotBlank(p.RES_Product_Address__StateCode__s)) {
            String stateCode = p.RES_Product_Address__StateCode__s;
            addr.put('state', SA_STATE_CODE_NAMES.containsKey(stateCode) ? SA_STATE_CODE_NAMES.get(stateCode) : stateCode);
        }
        if (String.isNotBlank(p.RES_Product_Address__PostalCode__s)) addr.put('postalCode', p.RES_Product_Address__PostalCode__s);
        if (String.isNotBlank(p.RES_Product_Address__CountryCode__s)) {
            String countryCode = p.RES_Product_Address__CountryCode__s;
            addr.put('country', COUNTRY_CODE_NAMES.containsKey(countryCode) ? COUNTRY_CODE_NAMES.get(countryCode) : countryCode);
        }
        return addr.isEmpty() ? null : JSON.serialize(addr);
    }

    /**
     * @description Builds the RES_Fixtures_Fittings array mapping Product2 boolean/picklist fields to SAP Z-codes.
     */
    @TestVisible
    private static List<Map<String, Object>> buildFixturesFittings(Product2 p, String triggerContext) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();

        Map<String, String> orientationCodes = new Map<String, String>{
            'North' => 'Z001', 'East' => 'Z002', 'South' => 'Z003', 'West' => 'Z004'
        };
        if (String.isNotBlank(p.RES_Orientation__c) && orientationCodes.containsKey(p.RES_Orientation__c)) {
            addChar(result, orientationCodes.get(p.RES_Orientation__c), triggerContext);
        }

        addBool(result, p.RES_Storeroom__c,      'Z005', 'Z006', triggerContext);
        addBool(result, p.RES_Elevated__c,        'Z007', 'Z008', triggerContext);
        addBool(result, p.RES_Terrace__c,         'Z009', 'Z010', triggerContext);
        addBool(result, p.RES_Roof_Terrace__c,    'Z011', 'Z012', triggerContext);
        addBool(result, p.RES_Entry_Courtyard__c, 'Z013', 'Z014', triggerContext);
        addBool(result, p.RES_Garage__c,          'Z015', 'Z016', triggerContext);
        addBool(result, p.RES_Pool__c,            'Z017', 'Z018', triggerContext);

        Map<String, String> idFinishCodes = new Map<String, String>{
            'Najdi' => 'Z019', 'Light Najdi' => 'Z020', 'Contemporary' => 'Z021'
        };
        if (String.isNotBlank(p.RES_ID_Finish__c) && idFinishCodes.containsKey(p.RES_ID_Finish__c)) {
            addChar(result, idFinishCodes.get(p.RES_ID_Finish__c), triggerContext);
        }

        addBool(result, p.RES_Drivers_Room__c,   'Z022', 'Z023', triggerContext);
        addBool(result, p.RES_Maids_Room__c,     'Z024', 'Z025', triggerContext);
        addBool(result, p.RES_Wadi_View__c,      'Z026', 'Z027', triggerContext);
        addBool(result, p.RES_Golf_View__c,      'Z028', 'Z029', triggerContext);
        addBool(result, p.RES_Panoramic_View__c, 'Z030', 'Z031', triggerContext);
        addBool(result, p.RES_Private__c,        'Z032', 'Z033', triggerContext);

        Map<String, String> conditionCodes = new Map<String, String>{
            'Soft Finish' => 'Z037', 'Shell' => 'Z038', 'Core' => 'Z039'
        };
        if (String.isNotBlank(p.RES_Condition__c) && conditionCodes.containsKey(p.RES_Condition__c)) {
            addChar(result, conditionCodes.get(p.RES_Condition__c), triggerContext);
        }

        addBool(result, p.RES_Furnished__c, 'Z042', 'Z043', triggerContext);

        return result;
    }

    private static void addBool(List<Map<String, Object>> r, Boolean val, String trueCode, String falseCode, String ctx) {
        addChar(r, val == true ? trueCode : falseCode, ctx);
    }

    private static void addChar(List<Map<String, Object>> r, String code, String ctx) {
        r.add(new Map<String, Object>{
            'RES_Fixtures_Fittings_Characteristics' => code,
            'Change_Indicator' => ctx
        });
    }

    /** @description Processes the SAP response body, logs error items, and returns true on success. */
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
            RES_IntegrationErrorLogger log = new RES_IntegrationErrorLogger(
                'Unit_Sync', '', errorMessage,
                JSON.serialize(service.getHeaders()), objectType, recordId,
                String.valueOf(service.getRequestBody()), service.getRequestMethod(),
                'Unit_Sync', service.getRetryCount(), 'Client Side'
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
                String sapExternalId = triggerContext == 'I' ? extractSAPExternalId(response.responseBody) : null;
                List<Product2> toUpdate = new List<Product2>();
                for (Product2 p : products) {
                    Product2 upd = new Product2(Id = p.Id, RES_Last_Sync_DateTime__c = System.now());
                    if (String.isNotBlank(sapExternalId)) {
                        upd.RES_Product_External_ID__c = sapExternalId;
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
            }

        } catch (Exception e) {
            System.debug('Exception occurred while calling the Product Integration Service: ' + e.getMessage());
        }
    }
}
