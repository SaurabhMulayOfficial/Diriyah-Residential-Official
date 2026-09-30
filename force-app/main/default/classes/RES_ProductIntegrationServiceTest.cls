/**
 * @description Tests for RES_ProductIntegrationService — Unit Sync payload builder and SAP callout.
 * @author      Roshan Jambhule
 * @date        2025-2026
 */
@isTest
private class RES_ProductIntegrationServiceTest {

    private static final Set<String> CUSTOM_ONLY_FIELDS = new Set<String>{
        'RES_Unit_Handover_Date__c',
        'RES_Type__c',
        'RES_Style__c',
        'RES_Unit_Size__c',
        'RES_Unit_Share__c',
        'StockKeepingUnit'
    };

    private static final Set<String> MIXED_FIELDS = new Set<String>{
        'Family', 'RES_Business_Entity__c', 'RES_Building__c',
        'AvailabilityDate', 'DiscontinuedDate', 'RES_Floor__c',
        'RES_Unit_Status__c', 'ProductCode', 'RES_Profit_Center__c',
        'RES_Orientation__c', 'RES_Storeroom__c', 'RES_Elevated__c',
        'RES_Unit_Handover_Date__c', 'RES_Type__c', 'StockKeepingUnit'
    };

    private static Product2 makeProduct() {
        return new Product2(
            Name               = 'TEST-UNIT',
            IsActive           = true,
            StockKeepingUnit   = 'SKU-001',
            ProductCode        = 'PC-TEST-001',
            Family             = '1004',
            RES_Floor__c       = '001',
            RES_Area_Type__c   = 'None',
            RES_Area__c        = 100,
            RES_Unit_Status__c = 'Available',
            RES_Type__c        = 'N',
            RES_Style__c       = '3-3A',
            RES_Unit_Size__c   = 180.5,
            RES_Unit_Share__c  = 12.5,
            RES_Unit_Handover_Date__c = Date.newInstance(2026, 6, 30)
        );
    }

    private static Map<String, String> toNameValueMap(List<Map<String, Object>> entries) {
        Map<String, String> m = new Map<String, String>();
        for (Map<String, Object> e : entries) {
            m.put(String.valueOf(e.get('name')), String.valueOf(e.get('value')));
        }
        return m;
    }

    private static Product2 insertProductWithoutTrigger(Product2 p) {
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId        = UserInfo.getOrganizationId(),
            RES_Triggers_Off__c = true
        );
        upsert cfg;
        insert p;
        cfg.RES_Triggers_Off__c = false;
        update cfg;
        return p;
    }

    private static Map<String, String> makeInventoryTypeMap() {
        return new Map<String, String>{ 'RES_Residential_Sales' => 'Y01', 'DEFAULT' => 'Z01' };
    }

    private static Map<String, String> makeFixtureBoolTrueMap() {
        return new Map<String, String>{
            'RES_Storeroom__c' => 'Z005', 'RES_Elevated__c' => 'Z007', 'RES_Terrace__c' => 'Z009',
            'RES_Roof_Terrace__c' => 'Z011', 'RES_Entry_Courtyard__c' => 'Z013', 'RES_Garage__c' => 'Z015',
            'RES_Pool__c' => 'Z017', 'RES_Drivers_Room__c' => 'Z022', 'RES_Maids_Room__c' => 'Z024',
            'RES_Wadi_View__c' => 'Z026', 'RES_Golf_View__c' => 'Z028', 'RES_Panoramic_View__c' => 'Z030',
            'RES_Private__c' => 'Z032', 'RES_Furnished__c' => 'Z042'
        };
    }

    private static Map<String, String> makeFixtureBoolFalseMap() {
        return new Map<String, String>{
            'RES_Storeroom__c' => 'Z006', 'RES_Elevated__c' => 'Z008', 'RES_Terrace__c' => 'Z010',
            'RES_Roof_Terrace__c' => 'Z012', 'RES_Entry_Courtyard__c' => 'Z014', 'RES_Garage__c' => 'Z016',
            'RES_Pool__c' => 'Z018', 'RES_Drivers_Room__c' => 'Z023', 'RES_Maids_Room__c' => 'Z025',
            'RES_Wadi_View__c' => 'Z027', 'RES_Golf_View__c' => 'Z029', 'RES_Panoramic_View__c' => 'Z031',
            'RES_Private__c' => 'Z033', 'RES_Furnished__c' => 'Z043'
        };
    }

    private static Boolean canConstruct() {
        return !new RES_APIConfigurationsDAO().getAPIConfiguration('GET', 'Unit_API').isEmpty();
    }

    @isTest
    static void testOneCustomField() {
        Product2 p = makeProduct();

        List<Map<String, Object>> result =
            RES_ProductIntegrationService.buildCustomFields(p, new Set<String>{ 'StockKeepingUnit' }, makeInventoryTypeMap(),
                new List<RES_Measurement__c>(), new Map<String, String>());

        Map<String, String> byName = toNameValueMap(result);
        Assert.isTrue(byName.containsKey('StockKeepingUnit'), 'StockKeepingUnit must be in CustomFields');
        Assert.areEqual('SKU-001', byName.get('StockKeepingUnit'), 'Value mismatch');
    }

    @isTest
    static void testMultipleCustomFields() {
        Product2 p = makeProduct();

        List<Map<String, Object>> result =
            RES_ProductIntegrationService.buildCustomFields(p, CUSTOM_ONLY_FIELDS, makeInventoryTypeMap(),
                new List<RES_Measurement__c>(), new Map<String, String>());

        Map<String, String> byName = toNameValueMap(result);
        Assert.areEqual('SKU-001',  byName.get('StockKeepingUnit'),       'StockKeepingUnit');
        Assert.isFalse(byName.containsKey('RES_Type'),  'RES_Type__c (root-excluded) must not appear directly');
        Assert.areEqual('3-3A',     byName.get('RES_Style'),              'RES_Style');
        Assert.areEqual('20260630', byName.get('RES_Unit_Handover_Date'), 'Date must be YYYYMMDD');
        Assert.isTrue(byName.containsKey('RES_Unit_Size'),  'RES_Unit_Size must be present');
        Assert.isTrue(byName.containsKey('RES_Unit_Share'), 'RES_Unit_Share must be present');
    }

    @isTest
    static void testNullFieldsSkipped() {
        Product2 p = new Product2(StockKeepingUnit = 'SKU-X');

        List<Map<String, Object>> result =
            RES_ProductIntegrationService.buildCustomFields(
                p, new Set<String>{ 'StockKeepingUnit', 'RES_Type__c', 'RES_Style__c' }, makeInventoryTypeMap(),
                new List<RES_Measurement__c>(), new Map<String, String>()
            );

        Map<String, String> byName = toNameValueMap(result);
        Assert.isTrue(byName.containsKey('StockKeepingUnit'), 'SKU must be present');
        Assert.isFalse(byName.containsKey('RES_Type'),        'Null field must be skipped');
        Assert.isFalse(byName.containsKey('RES_Style'),       'Null field must be skipped');
    }

    @isTest
    static void testAllCustomFieldsBlank() {
        Product2 p = new Product2();

        List<Map<String, Object>> result =
            RES_ProductIntegrationService.buildCustomFields(
                p, new Set<String>{ 'RES_Type__c', 'RES_Style__c', 'RES_Building_Number__c' }, makeInventoryTypeMap(),
                new List<RES_Measurement__c>(), new Map<String, String>()
            );

        Assert.isTrue(result.isEmpty(),
            'All-blank custom fields must produce an empty list');
    }

    @isTest
    static void testRootFieldsExcluded() {
        Product2 p = makeProduct();

        List<Map<String, Object>> result =
            RES_ProductIntegrationService.buildCustomFields(p, MIXED_FIELDS, makeInventoryTypeMap(),
                new List<RES_Measurement__c>(), new Map<String, String>());

        Set<String> names = new Set<String>();
        for (Map<String, Object> e : result) names.add((String) e.get('name'));

        for (String rootSf : RES_ProductIntegrationService.ROOT_FIELD_SF_NAMES) {
            String sapName = rootSf.endsWith('__c') ? rootSf.removeEnd('__c') : rootSf;
            Assert.isFalse(names.contains(sapName),
                'Root field ' + rootSf + ' must not appear in RES_CustomFields');
        }
    }

    @isTest
    static void testFixtureFieldsExcluded() {
        Product2 p = makeProduct();

        List<Map<String, Object>> result =
            RES_ProductIntegrationService.buildCustomFields(p, MIXED_FIELDS, makeInventoryTypeMap(),
                new List<RES_Measurement__c>(), new Map<String, String>());

        Set<String> names = new Set<String>();
        for (Map<String, Object> e : result) names.add((String) e.get('name'));

        for (String fixSf : RES_ProductIntegrationService.FIXTURES_SF_NAMES) {
            String sapName = fixSf.endsWith('__c') ? fixSf.removeEnd('__c') : fixSf;
            Assert.isFalse(names.contains(sapName),
                'Fixture field ' + fixSf + ' must not appear in RES_CustomFields');
        }
    }

    @isTest
    static void testDateFieldFormattedYYYYMMDD() {
        Product2 p = makeProduct();

        List<Map<String, Object>> result =
            RES_ProductIntegrationService.buildCustomFields(
                p, new Set<String>{ 'RES_Unit_Handover_Date__c' }, makeInventoryTypeMap(),
                new List<RES_Measurement__c>(), new Map<String, String>()
            );

        Map<String, String> byName = toNameValueMap(result);
        Assert.isTrue(byName.containsKey('RES_Unit_Handover_Date'), 'Date field must be present');
        Assert.areEqual('20260630', byName.get('RES_Unit_Handover_Date'), 'Date format must be YYYYMMDD');
    }

    @isTest
    static void testSapNameDerivation() {
        Product2 p = makeProduct();

        List<Map<String, Object>> result =
            RES_ProductIntegrationService.buildCustomFields(
                p, new Set<String>{ 'RES_Style__c', 'StockKeepingUnit' }, makeInventoryTypeMap(),
                new List<RES_Measurement__c>(), new Map<String, String>()
            );

        Set<String> names = new Set<String>();
        for (Map<String, Object> e : result) names.add((String) e.get('name'));

        Assert.isTrue(names.contains('RES_Style'),         'RES_Style__c must produce SAP name RES_Style');
        Assert.isFalse(names.contains('RES_Style__c'),     '__c suffix must not appear in payload');
        Assert.isTrue(names.contains('StockKeepingUnit'),  'Non-__c field must remain unchanged');
    }

    @isTest
    static void testMeasurementOverlapDetected() {
        List<Map<String, Object>> measList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'RES_Measurement_Type' => 'Z002',
                'RES_Measurement_From' => '2026-09-01',
                'RES_Measurement_To'   => '2026-10-31'
            },
            new Map<String, Object>{
                'RES_Measurement_Type' => 'Z002',
                'RES_Measurement_From' => '2026-09-26',
                'RES_Measurement_To'   => '2026-10-11'
            }
        };

        String error = RES_ProductIntegrationService.validateMeasurements(measList);

        Assert.isNotNull(error, 'Overlapping periods must produce a validation error');
        Assert.isTrue(error.containsIgnoreCase('overlap'), 'Error must mention overlap');
    }

    @isTest
    static void testMeasurementNonOverlapPasses() {
        List<Map<String, Object>> measList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'RES_Measurement_Type' => 'Z002',
                'RES_Measurement_From' => '2026-09-26',
                'RES_Measurement_To'   => '2026-10-11'
            },
            new Map<String, Object>{
                'RES_Measurement_Type' => 'Z002',
                'RES_Measurement_From' => '2026-10-12',
                'RES_Measurement_To'   => '2026-10-31'
            }
        };

        String error = RES_ProductIntegrationService.validateMeasurements(measList);

        Assert.isNull(error, 'Adjacent non-overlapping periods must pass validation');
    }

    @isTest
    static void testDifferentTypesDoNotConflict() {
        List<Map<String, Object>> measList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'RES_Measurement_Type' => 'Z002',
                'RES_Measurement_From' => '2026-09-26',
                'RES_Measurement_To'   => '2026-10-11'
            },
            new Map<String, Object>{
                'RES_Measurement_Type' => 'Z007',
                'RES_Measurement_From' => '2026-09-26',
                'RES_Measurement_To'   => '2026-10-11'
            }
        };

        String error = RES_ProductIntegrationService.validateMeasurements(measList);

        Assert.isNull(error, 'Same period for different types must not conflict');
    }

    @isTest
    static void testDuplicatePeriodDetected() {
        List<Map<String, Object>> measList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'RES_Measurement_Type' => 'Z002',
                'RES_Measurement_From' => '2026-09-26',
                'RES_Measurement_To'   => '2026-10-11'
            },
            new Map<String, Object>{
                'RES_Measurement_Type' => 'Z002',
                'RES_Measurement_From' => '2026-09-26',
                'RES_Measurement_To'   => '2026-10-11'
            }
        };

        String error = RES_ProductIntegrationService.validateMeasurements(measList);

        Assert.isNotNull(error, 'Identical period (duplicate) must be caught as overlap');
    }

    @isTest
    static void testMeasurementFromAfterTo() {
        List<Map<String, Object>> measList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'RES_Measurement_Type' => 'Z002',
                'RES_Measurement_From' => '2026-10-31',
                'RES_Measurement_To'   => '2026-09-01'
            }
        };

        String error = RES_ProductIntegrationService.validateMeasurements(measList);

        Assert.isNotNull(error, 'From > To must produce a validation error');
    }

    @isTest
    static void testEmptyMeasurementListPasses() {
        String error = RES_ProductIntegrationService.validateMeasurements(
            new List<Map<String, Object>>()
        );
        Assert.isNull(error, 'Empty list must not produce a validation error');
    }

    @isTest
    static void testHydrateRequestBodyInsert() {
        Product2 p = new Product2(
            Name               = 'HRB-INSERT',
            IsActive           = true,
            StockKeepingUnit   = 'SKU-HRB-I',
            Family             = '1004',
            ProductCode        = 'PC-HRB-I',
            RES_Floor__c       = '001',
            RES_Area_Type__c   = 'None',
            RES_Area__c        = 120,
            RES_Unit_Status__c = 'Available',
            RES_Type__c        = 'N',
            RES_Unit_Handover_Date__c = Date.newInstance(2026, 6, 30)
        );
        insertProductWithoutTrigger(p);

        Test.startTest();
        String body = RES_ProductIntegrationService.hydrateRequestBody(
            new List<Product2>{ p }, 'I'
        );
        Test.stopTest();

        Assert.isNotNull(body, 'Payload must not be null');
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Assert.areEqual('I', parsed.get('Change_Indicator'), 'INSERT must send Change_Indicator=I');
        Assert.areEqual('', parsed.get('RES_Rental_Object'), 'INSERT must send RES_Rental_Object as empty string');
        Assert.isTrue(parsed.containsKey('RES_CustomFields'), 'Payload must include RES_CustomFields');
        List<Object> cfs = (List<Object>) parsed.get('RES_CustomFields');
        Assert.isTrue(cfs.size() > 0, 'RES_CustomFields must be non-empty');
    }

    @isTest
    static void testHydrateRequestBodyUpdate() {
        Product2 p = new Product2(
            Name                        = 'HRB-UPDATE',
            IsActive                    = true,
            StockKeepingUnit            = 'SKU-HRB-U',
            RES_Type__c                 = 'N',
            RES_Product_External_ID__c  = '1000/200/11002876'
        );
        insertProductWithoutTrigger(p);

        Test.startTest();
        String body = RES_ProductIntegrationService.hydrateRequestBody(
            new List<Product2>{ p }, 'U'
        );
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Assert.areEqual('U',        parsed.get('Change_Indicator'),  'UPDATE must send Change_Indicator=U');
        Assert.areEqual('11002876', parsed.get('RES_Rental_Object'), 'UPDATE must include unit number from external ID');
    }

    @isTest
    static void testHydrateRequestBodyEmptyCustomFields() {
        Product2 p = new Product2(Name = 'HRB-EMPTY', IsActive = true);
        insertProductWithoutTrigger(p);

        Test.startTest();
        try {
            RES_ProductIntegrationService.hydrateRequestBody(new List<Product2>{ p }, 'I');
            Assert.fail('Expected RES_IntegrationException for empty CustomFields');
        } catch (RES_IntegrationException ex) {
            Assert.isTrue(ex.getMessage().containsIgnoreCase('CustomFields'),
                'Exception message must mention CustomFields');
        }
        Test.stopTest();
    }

    @isTest
    static void testEffectiveContextOverrideWhenExternalIdSet() {
        Product2 p = new Product2(
            Name                       = 'HRB-OVERRIDE',
            IsActive                   = true,
            StockKeepingUnit           = 'SKU-OVR',
            RES_Type__c                = 'N',
            RES_Product_External_ID__c = '1000/200/11002876'
        );
        insertProductWithoutTrigger(p);

        Test.startTest();
        String body = RES_ProductIntegrationService.hydrateRequestBody(
            new List<Product2>{ p }, 'I'
        );
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Assert.areEqual('U', parsed.get('Change_Indicator'),
            'Product with existing external ID must always send Change_Indicator=U');
        Assert.isNotNull(parsed.get('RES_Rental_Object'),
            'RES_Rental_Object must be included when external ID is present');
    }

    @isTest
    static void testBuildFixturesFittingsStoreroomTrue() {
        Product2 p = new Product2(RES_Storeroom__c = true);

        List<Map<String, Object>> fixtures =
            RES_ProductIntegrationService.buildFixturesFittings(p, 'I', makeFixtureBoolTrueMap(), makeFixtureBoolFalseMap());

        Boolean foundZ005 = false;
        for (Map<String, Object> f : fixtures) {
            if ('Z005'.equals(String.valueOf(f.get('RES_Fixtures_Fittings_Characteristics')))) {
                foundZ005 = true;
                Assert.areEqual('I', f.get('Change_Indicator'), 'Must use Change_Indicator I');
            }
        }
        Assert.isTrue(foundZ005, 'Storeroom true must produce Z005 fixture entry');
    }

    @isTest
    static void testBuildFixturesFittingsStoreroomFalse() {
        // false must NOT produce a No code — absence already signals "not present" to SAP
        Product2 p = new Product2(RES_Storeroom__c = false);

        List<Map<String, Object>> fixtures =
            RES_ProductIntegrationService.buildFixturesFittings(p, 'I', makeFixtureBoolTrueMap(), makeFixtureBoolFalseMap());

        for (Map<String, Object> f : fixtures) {
            String code = String.valueOf(f.get('RES_Fixtures_Fittings_Characteristics'));
            Assert.isTrue(!'Z005'.equals(code) && !'Z006'.equals(code),
                'Storeroom false must not produce Z005 or Z006 — got: ' + code);
        }
    }

    @isTest
    static void testBuildFixturesFittingsOrientationNorth() {
        Product2 p = new Product2(RES_Orientation__c = 'Z001');

        List<Map<String, Object>> fixtures =
            RES_ProductIntegrationService.buildFixturesFittings(p, 'I', makeFixtureBoolTrueMap(), makeFixtureBoolFalseMap());

        Boolean foundZ001 = false;
        for (Map<String, Object> f : fixtures) {
            if ('Z001'.equals(String.valueOf(f.get('RES_Fixtures_Fittings_Characteristics')))) {
                foundZ001 = true;
                Assert.areEqual('I', f.get('Change_Indicator'), 'Must use Change_Indicator I');
            }
        }
        Assert.isTrue(foundZ001, 'Orientation=North must produce Z001 fixture characteristic');
    }

    @isTest
    static void testBuildFixturesFittingsIdFinishContemporary() {
        Product2 p = new Product2(RES_ID_Finish__c = 'Z021');

        List<Map<String, Object>> fixtures =
            RES_ProductIntegrationService.buildFixturesFittings(p, 'I', makeFixtureBoolTrueMap(), makeFixtureBoolFalseMap());

        Boolean foundZ021 = false;
        for (Map<String, Object> f : fixtures) {
            if ('Z021'.equals(String.valueOf(f.get('RES_Fixtures_Fittings_Characteristics')))) {
                foundZ021 = true;
                Assert.areEqual('I', f.get('Change_Indicator'), 'Must use Change_Indicator I');
            }
        }
        Assert.isTrue(foundZ021, 'ID_Finish=Contemporary must produce Z021 fixture characteristic');
    }

    @isTest
    static void testBuildFixturesFittingsUpdateContext() {
        Product2 p = new Product2(RES_Storeroom__c = true);

        List<Map<String, Object>> fixtures =
            RES_ProductIntegrationService.buildFixturesFittings(p, 'U', makeFixtureBoolTrueMap(), makeFixtureBoolFalseMap());

        Boolean foundZ005WithU = false;
        for (Map<String, Object> f : fixtures) {
            if ('Z005'.equals(String.valueOf(f.get('RES_Fixtures_Fittings_Characteristics')))) {
                foundZ005WithU = 'U'.equals(String.valueOf(f.get('Change_Indicator')));
            }
        }
        Assert.isTrue(foundZ005WithU, 'Update context must produce Z005 with Change_Indicator U');
    }

    @isTest
    static void testHydrateBodyInsertIncludesFixtures() {
        Product2 p = new Product2(
            Name             = 'HRB-FIX-INSERT',
            IsActive         = true,
            StockKeepingUnit = 'SKU-FIX-I',
            RES_Type__c      = 'N',
            RES_Storeroom__c = true
        );
        insertProductWithoutTrigger(p);

        Test.startTest();
        String body = RES_ProductIntegrationService.hydrateRequestBody(
            new List<Product2>{ p }, 'I'
        );
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Assert.isTrue(parsed.containsKey('RES_Fixtures_Fittings'),
            'INSERT payload must include RES_Fixtures_Fittings');
        List<Object> fixtures = (List<Object>) parsed.get('RES_Fixtures_Fittings');
        Assert.isTrue(fixtures != null && !fixtures.isEmpty(),
            'RES_Fixtures_Fittings must be non-empty on INSERT');
    }

    @isTest
    static void testHydrateBodyUpdateIncludesFixtures() {
        // UPDATE with no prior fixture sync (null RES_Fixtures_Last_Sync__c) → fixtureCtx='I', fixtures included
        Product2 p = new Product2(
            Name                       = 'HRB-FIX-UPDATE',
            IsActive                   = true,
            StockKeepingUnit           = 'SKU-FIX-U',
            RES_Type__c                = 'N',
            RES_Storeroom__c           = true,
            RES_Product_External_ID__c = '1000/200/11002876'
        );
        insertProductWithoutTrigger(p);

        Test.startTest();
        String body = RES_ProductIntegrationService.hydrateRequestBody(
            new List<Product2>{ p }, 'U'
        );
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Assert.isTrue(parsed.containsKey('RES_Fixtures_Fittings'),
            'UPDATE payload must include RES_Fixtures_Fittings when RES_Fixtures_Last_Sync__c is null');
        List<Object> fixtures = (List<Object>) parsed.get('RES_Fixtures_Fittings');
        Assert.isTrue(fixtures != null && !fixtures.isEmpty(),
            'RES_Fixtures_Fittings must be non-empty when Storeroom is checked');
    }

    @isTest
    static void testBuildConditionsEmptyMappingsReturnsEmpty() {
        List<Map<String, Object>> conditions = RES_ProductIntegrationService.buildConditions(
            new List<RES_Condition_Mapping__mdt>(),
            new List<AttributeBasedAdjustment>(),
            new Map<Id, String>(),
            new List<ProductAttributeDefinition>(),
            'I'
        );
        Assert.isTrue(conditions.isEmpty(), 'No condition mappings must produce empty conditions list');
    }

    @isTest
    static void testBuildConditionsProductAttributeHandling() {
        RES_Condition_Mapping__mdt mapping = new RES_Condition_Mapping__mdt(
            RES_Condition_Type__c     = 'Y100',
            RES_Formula__c            = 'D',
            RES_Conditions_Purpose__c = 'I',
            RES_Handling__c           = 'Product_Attribute',
            RES_Attribute_Name__c     = 'Pricing Option',
            RES_Parameter_1__c        = 'Z007',
            RES_Parameter_2__c        = null
        );
        ProductAttributeDefinition pad = new ProductAttributeDefinition(
            DefaultValue      = '50000',
            RES_Valid_From__c = Date.newInstance(2026, 1, 1),
            RES_Valid_To__c   = Date.newInstance(2026, 12, 31)
        );
        pad.put('Name', 'Pricing Option');

        List<Map<String, Object>> conditions = RES_ProductIntegrationService.buildConditions(
            new List<RES_Condition_Mapping__mdt>{ mapping },
            new List<AttributeBasedAdjustment>(),
            new Map<Id, String>(),
            new List<ProductAttributeDefinition>{ pad },
            'I'
        );

        Assert.areEqual(1, conditions.size(), 'One condition must be built from PAD data');
        Map<String, Object> cond = conditions[0];
        Assert.areEqual('Y100', cond.get('RES_Condition_Type'),       'Condition type from mapping');
        Assert.areEqual(50000,  ((Decimal) cond.get('RES_Condition_Price')).intValue(), 'Price from PAD DefaultValue');
        Assert.areEqual('I',         cond.get('Change_Indicator'),        'CI must equal triggerContext');
        Assert.areEqual('Z007',      cond.get('RES_Parameter_1'),         'Parameter_1 from mapping');
        Assert.areEqual('',          cond.get('RES_Parameter_2'),         'Parameter_2 must be empty string when null');
        Assert.areEqual('2026-01-01', cond.get('RES_Condition_Valid_From'), 'Valid_From from PAD');
        Assert.areEqual('2026-12-31', cond.get('RES_Condition_Valid_To'),   'Valid_To from PAD');
    }

    @isTest
    static void testBuildConditionsProductAttributeSkipWhenNoPadMatch() {
        RES_Condition_Mapping__mdt mapping = new RES_Condition_Mapping__mdt(
            RES_Condition_Type__c = 'Y100',
            RES_Formula__c        = 'D',
            RES_Handling__c       = 'Product_Attribute',
            RES_Attribute_Name__c = 'Missing Attribute'
        );

        List<Map<String, Object>> conditions = RES_ProductIntegrationService.buildConditions(
            new List<RES_Condition_Mapping__mdt>{ mapping },
            new List<AttributeBasedAdjustment>(),
            new Map<Id, String>(),
            new List<ProductAttributeDefinition>(),
            'I'
        );

        Assert.isTrue(conditions.isEmpty(),
            'Condition must be skipped when no PAD matches the attribute name');
    }

    @isTest
    static void testBuildConditionsChangeIndicatorEqualsContext() {
        RES_Condition_Mapping__mdt mapping = new RES_Condition_Mapping__mdt(
            RES_Condition_Type__c     = 'Y101',
            RES_Formula__c            = 'D',
            RES_Conditions_Purpose__c = 'I',
            RES_Handling__c           = 'Product_Attribute',
            RES_Attribute_Name__c     = 'Area Price',
            RES_Parameter_1__c        = 'Z007'
        );
        ProductAttributeDefinition pad = new ProductAttributeDefinition(DefaultValue = '90000');
        pad.put('Name', 'Area Price');

        List<Map<String, Object>> conditions = RES_ProductIntegrationService.buildConditions(
            new List<RES_Condition_Mapping__mdt>{ mapping },
            new List<AttributeBasedAdjustment>(),
            new Map<Id, String>(),
            new List<ProductAttributeDefinition>{ pad },
            'U'
        );

        Assert.areEqual(1, conditions.size());
        Assert.areEqual('U', conditions[0].get('Change_Indicator'),
            'Change_Indicator must equal the triggerContext passed in (U for UPDATE)');
    }

    @isTest
    static void testSyncProductsSuccessStampsLastSyncDateTime() {
        if (!canConstruct()) return;

        Product2 p = new Product2(
            Name               = 'SP-SUCCESS',
            IsActive           = true,
            StockKeepingUnit   = 'SKU-SP-OK',
            RES_Type__c        = 'N',
            Family             = '1004',
            RES_Floor__c       = '001',
            RES_Area_Type__c   = 'None',
            RES_Area__c        = 100.0,
            RES_Unit_Status__c = 'Available'
        );
        insertProductWithoutTrigger(p);

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody =
            '{"Return":{"item":{"Type":"S","Message":"Unit created","MessageV4":"RO 1000/200/11002876"}}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        RES_ProductIntegrationService.syncProducts(
            new List<Product2>{ [SELECT Id, Name, Family, ProductCode,
                                  RES_Floor__c, RES_Area_Type__c, RES_Area__c,
                                  RES_Unit_Status__c, RES_Type__c, StockKeepingUnit,
                                  RES_Product_External_ID__c, RES_Last_Sync_DateTime__c,
                                  RES_Fixtures_Last_Sync__c,
                                  RES_Profit_Center__c, AvailabilityDate, DiscontinuedDate,
                                  RES_Orientation__c, RES_Storeroom__c, RES_Elevated__c,
                                  RES_Terrace__c, RES_Roof_Terrace__c, RES_Entry_Courtyard__c,
                                  RES_Garage__c, RES_Pool__c, RES_ID_Finish__c,
                                  RES_Drivers_Room__c, RES_Maids_Room__c, RES_Wadi_View__c,
                                  RES_Golf_View__c, RES_Panoramic_View__c, RES_Private__c,
                                  RES_Condition__c, RES_Furnished__c,
                                  RES_Business_Entity__r.RES_Company_Code__c,
                                  RES_Business_Entity__r.RES_Business_Entity_Id__c,
                                  RES_Building__r.RES_Property_Id__c,
                                  RecordType.DeveloperName,
                                  RES_Product_Address__Street__s,
                                  RES_Product_Address__City__s,
                                  RES_Product_Address__PostalCode__s,
                                  RES_Product_Address__CountryCode__s,
                                  RES_Product_Address__StateCode__s
                                  FROM Product2 WHERE Id = :p.Id] },
            'GET', 'I'
        );
        Test.stopTest();

        Product2 after = [SELECT RES_Last_Sync_DateTime__c, RES_Product_External_ID__c
                           FROM Product2 WHERE Id = :p.Id];
        Assert.isNotNull(after.RES_Last_Sync_DateTime__c,
            'RES_Last_Sync_DateTime__c must be stamped after a successful SAP callout');
        Assert.areEqual(1, mock.businessCallCount, 'Exactly one SAP callout must be made');
    }

    @isTest
    static void testSyncProductsErrorResponseDoesNotStamp() {
        if (!canConstruct()) return;

        Product2 p = new Product2(
            Name               = 'SP-ERROR',
            IsActive           = true,
            StockKeepingUnit   = 'SKU-SP-ERR',
            RES_Type__c        = 'N',
            Family             = '1004',
            RES_Floor__c       = '001',
            RES_Area_Type__c   = 'None',
            RES_Area__c        = 100.0,
            RES_Unit_Status__c = 'Available'
        );
        insertProductWithoutTrigger(p);

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody =
            '{"Return":{"item":{"Type":"E","Message":"Unit sync failed - validation error"}}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        RES_ProductIntegrationService.syncProducts(
            new List<Product2>{ [SELECT Id, Name, Family, ProductCode,
                                  RES_Floor__c, RES_Area_Type__c, RES_Area__c,
                                  RES_Unit_Status__c, RES_Type__c, StockKeepingUnit,
                                  RES_Product_External_ID__c, RES_Last_Sync_DateTime__c,
                                  RES_Fixtures_Last_Sync__c,
                                  RES_Profit_Center__c, AvailabilityDate, DiscontinuedDate,
                                  RES_Orientation__c, RES_Storeroom__c, RES_Elevated__c,
                                  RES_Terrace__c, RES_Roof_Terrace__c, RES_Entry_Courtyard__c,
                                  RES_Garage__c, RES_Pool__c, RES_ID_Finish__c,
                                  RES_Drivers_Room__c, RES_Maids_Room__c, RES_Wadi_View__c,
                                  RES_Golf_View__c, RES_Panoramic_View__c, RES_Private__c,
                                  RES_Condition__c, RES_Furnished__c,
                                  RES_Business_Entity__r.RES_Company_Code__c,
                                  RES_Business_Entity__r.RES_Business_Entity_Id__c,
                                  RES_Building__r.RES_Property_Id__c,
                                  RecordType.DeveloperName,
                                  RES_Product_Address__Street__s,
                                  RES_Product_Address__City__s,
                                  RES_Product_Address__PostalCode__s,
                                  RES_Product_Address__CountryCode__s,
                                  RES_Product_Address__StateCode__s
                                  FROM Product2 WHERE Id = :p.Id] },
            'GET', 'I'
        );
        Test.stopTest();

        Product2 after = [SELECT RES_Last_Sync_DateTime__c FROM Product2 WHERE Id = :p.Id];
        Assert.isNull(after.RES_Last_Sync_DateTime__c,
            'RES_Last_Sync_DateTime__c must NOT be stamped when SAP returns an error');
    }

    @isTest
    static void testSyncProductsMultiRecordThrows() {
        if (!canConstruct()) return;

        Product2 p1 = new Product2(Name = 'MULTI-A', IsActive = true, StockKeepingUnit = 'SKU-MA', RES_Type__c = 'N');
        Product2 p2 = new Product2(Name = 'MULTI-B', IsActive = true, StockKeepingUnit = 'SKU-MB', RES_Type__c = 'N');
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId = UserInfo.getOrganizationId(), RES_Triggers_Off__c = true
        );
        upsert cfg;
        insert new List<Product2>{ p1, p2 };
        cfg.RES_Triggers_Off__c = false;
        update cfg;

        RES_IntegrationTestDataFactory.primeSapToken();

        Test.startTest();
        try {
            RES_ProductIntegrationService.syncProducts(new List<Product2>{ p1, p2 }, 'GET', 'I');
            Assert.fail('Expected RES_IntegrationException for multi-record call');
        } catch (RES_IntegrationException ex) {
            Assert.isTrue(ex.getMessage().containsIgnoreCase('exactly 1'),
                'Exception must enforce the single-record contract');
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncProductsCalloutExceptionDoesNotPropagate() {
        if (!canConstruct()) return;

        Product2 p = new Product2(
            Name               = 'SP-EXCEPT',
            IsActive           = true,
            StockKeepingUnit   = 'SKU-SP-EX',
            RES_Type__c        = 'N',
            Family             = '1004',
            RES_Floor__c       = '001',
            RES_Area_Type__c   = 'None',
            RES_Area__c        = 100.0,
            RES_Unit_Status__c = 'Available'
        );
        insertProductWithoutTrigger(p);

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.throwOnBusiness = true;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            RES_ProductIntegrationService.syncProducts(
                new List<Product2>{ [SELECT Id, Name, Family, ProductCode,
                                      RES_Floor__c, RES_Area_Type__c, RES_Area__c,
                                      RES_Unit_Status__c, RES_Type__c, StockKeepingUnit,
                                      RES_Product_External_ID__c, RES_Last_Sync_DateTime__c,
                                      RES_Fixtures_Last_Sync__c,
                                      RES_Profit_Center__c, AvailabilityDate, DiscontinuedDate,
                                      RES_Orientation__c, RES_Storeroom__c, RES_Elevated__c,
                                      RES_Terrace__c, RES_Roof_Terrace__c, RES_Entry_Courtyard__c,
                                      RES_Garage__c, RES_Pool__c, RES_ID_Finish__c,
                                      RES_Drivers_Room__c, RES_Maids_Room__c, RES_Wadi_View__c,
                                      RES_Golf_View__c, RES_Panoramic_View__c, RES_Private__c,
                                      RES_Condition__c, RES_Furnished__c,
                                      RES_Business_Entity__r.RES_Company_Code__c,
                                      RES_Business_Entity__r.RES_Business_Entity_Id__c,
                                      RES_Building__r.RES_Property_Id__c,
                                      RecordType.DeveloperName,
                                      RES_Product_Address__Street__s,
                                      RES_Product_Address__City__s,
                                      RES_Product_Address__PostalCode__s,
                                      RES_Product_Address__CountryCode__s,
                                      RES_Product_Address__StateCode__s
                                      FROM Product2 WHERE Id = :p.Id] },
                'GET', 'I'
            );
        } catch (Exception ex) {
            Assert.fail('syncProducts must not propagate callout exceptions: ' + ex.getMessage());
        }
        Test.stopTest();
    }

    // ── Change A: ExternalId format validation ────────────────────────────────

    @isTest
    static void testValidateSapExternalIdValidFormat() {
        String err = RES_ProductIntegrationService.validateSapExternalIdFormat('1000/140/11002912');
        Assert.isNull(err, 'Valid SAP ExternalId must return null (no error)');
    }

    @isTest
    static void testValidateSapExternalIdProductCodeFails() {
        String err = RES_ProductIntegrationService.validateSapExternalIdFormat('WS-FN-6BV-Rj-005');
        Assert.isNotNull(err, 'ProductCode-style ExternalId must be rejected');
        Assert.isTrue(err.containsIgnoreCase('format'), 'Error must mention the format requirement');
    }

    @isTest
    static void testValidateSapExternalIdNoSlashFails() {
        String err = RES_ProductIntegrationService.validateSapExternalIdFormat('11002912');
        Assert.isNotNull(err, 'A bare number without slashes must be rejected as invalid SAP format');
    }

    @isTest
    static void testValidateSapExternalIdBlankAllowed() {
        Assert.isNull(
            RES_ProductIntegrationService.validateSapExternalIdFormat(''),
            'Blank ExternalId must return null — blank signals an INSERT, not a format error'
        );
        Assert.isNull(
            RES_ProductIntegrationService.validateSapExternalIdFormat(null),
            'Null ExternalId must return null — null signals an INSERT, not a format error'
        );
    }

    @isTest
    static void testHydrateBodyThrowsForMalformedExternalId() {
        Product2 p = new Product2(
            Name                       = 'BAD-EXT-ID',
            IsActive                   = true,
            StockKeepingUnit           = 'SKU-BADID',
            RES_Type__c                = 'N',
            RES_Product_External_ID__c = 'WS-FN-6BV-Rj-005'  // ProductCode pre-set by upload sheet
        );
        insertProductWithoutTrigger(p);

        Test.startTest();
        try {
            RES_ProductIntegrationService.hydrateRequestBody(new List<Product2>{ p }, 'U');
            Assert.fail('Expected RES_IntegrationException for ExternalId that does not match SAP format');
        } catch (RES_IntegrationException ex) {
            Assert.isTrue(ex.getMessage().containsIgnoreCase('validation failed'),
                'Exception message must describe the ExternalId format problem');
        }
        Test.stopTest();
    }

    // ── Change B: UOM mapping enforcement ────────────────────────────────────

    @isTest
    static void testMeasurementWithKnownUomIsMappedAndIncluded() {
        Product2 p = new Product2(
            Name               = 'UOM-SQRMTR',
            IsActive           = true,
            StockKeepingUnit   = 'SKU-M2',
            RES_Type__c        = 'N',
            RES_Unit_Status__c = 'Available'
        );
        insertProductWithoutTrigger(p);

        // insertProductWithoutTrigger already created the config switch; query and reuse it
        RES_Config_Switch__c cfg = [SELECT Id FROM RES_Config_Switch__c
                                    WHERE SetupOwnerId = :UserInfo.getOrganizationId() LIMIT 1];
        cfg.RES_Triggers_Off__c = true;
        update cfg;
        RES_Measurement__c m = new RES_Measurement__c(
            RES_Product__c             = p.Id,
            RES_Measurement_Type__c    = 'Z008',
            RES_Measurement_Amount__c  = 75.0,
            RES_Measurement_From__c    = Date.newInstance(2026, 1, 1),
            RES_Measurement_To__c      = Date.newInstance(2099, 12, 31),
            RES_Unit_Of_Measurement__c = 'Sqr Mtr'
        );
        insert m;
        cfg.RES_Triggers_Off__c = false;
        update cfg;

        Test.startTest();
        String body = RES_ProductIntegrationService.hydrateRequestBody(new List<Product2>{ p }, 'I');
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Assert.isTrue(parsed.containsKey('RES_Measurements'),
            'Payload must include RES_Measurements when a valid-UOM measurement exists');
        List<Object> mList = (List<Object>) parsed.get('RES_Measurements');
        Assert.isFalse(mList.isEmpty(), 'Measurement list must not be empty');
        Map<String, Object> mPayload = (Map<String, Object>) mList[0];
        Assert.areEqual('M2', mPayload.get('RES_Unit_Of_Measurement'),
            'Sqr Mtr must be mapped to SAP UOM code M2 via the UOM MDT entry');
    }

    // ── Change C: "Already Exist" reconciliation label ────────────────────────

    @isTest
    static void testAlreadyExistResponseLogsReconciliationRequired() {
        if (!canConstruct()) return;

        Product2 p = new Product2(
            Name             = 'RECON-TEST',
            IsActive         = true,
            StockKeepingUnit = 'SKU-RECON',
            RES_Type__c      = 'N'
        );
        insertProductWithoutTrigger(p);

        RES_IntegrationTestDataFactory.primeSapToken();

        Test.startTest();
        RES_ProductIntegrationService svc = new RES_ProductIntegrationService('GET');
        String alreadyExistBody =
            '{"Return":{"item":{"Type":"E","Message":"Number of Rental Unit Already Exist"}}}';
        Boolean result = RES_ProductIntegrationService.processResponse(
            alreadyExistBody, svc, p.Id, 'Product2'
        );
        Test.stopTest();

        Assert.isFalse(result, 'SAP error response must return false');
        List<RES_Integration_Log__c> logs = [
            SELECT RES_Type_of_Failure__c
            FROM   RES_Integration_Log__c
            WHERE  RES_Record_Id__c    = :p.Id
            AND    RES_Request_Name__c = 'Unit_Sync'
            LIMIT  1
        ];
        Assert.isFalse(logs.isEmpty(),
            'An integration error log must be created for the Already Exist response');
        Assert.areEqual('Reconciliation Required', logs[0].RES_Type_of_Failure__c,
            'SAP "Already Exist" error must be classified as Reconciliation Required, not Client Side');
    }
}
