@IsTest
private class RES_IngestionConfigTest {

    @IsTest
    static void testActiveLayoutsAndRetrieval() {
        Test.startTest();
        List<RES_IngestionConfig.Layout> layouts = RES_IngestionConfig.activeLayouts();
        List<RES_IngestionConfig.Layout> cachedLayouts = RES_IngestionConfig.activeLayouts();
        Test.stopTest();

        Assert.areEqual(layouts.size(), cachedLayouts.size(), 'Cached layouts should match first call');
        if (!layouts.isEmpty()) {
            RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(layouts[0].code);
            Assert.isNotNull(layout, 'Should find layout by active code');
        }
        Assert.isNull(RES_IngestionConfig.layoutByCode(''), 'Blank code should return null');
        Assert.isNull(RES_IngestionConfig.layoutByCode('NON_EXISTENT_CODE'), 'Invalid code should return null');
    }

    @IsTest
    static void testColumnMaps() {
        Test.startTest();
        List<RES_IngestionConfig.ColumnMap> maps = RES_IngestionConfig.columnMaps('RESIDENTIAL_SALES');
        List<RES_IngestionConfig.ColumnMap> cachedMaps = RES_IngestionConfig.columnMaps('RESIDENTIAL_SALES');
        Test.stopTest();

        Assert.areEqual(maps.size(), cachedMaps.size(), 'Column maps should be cached');
        Assert.isTrue(RES_IngestionConfig.columnMaps('').isEmpty(), 'Blank layout code should return empty list');
    }

    @IsTest
    static void testTargetMaps() {
        Test.startTest();
        List<RES_IngestionConfig.TargetMap> maps = RES_IngestionConfig.targetMaps('RESIDENTIAL_SALES');
        List<RES_IngestionConfig.TargetMap> cachedMaps = RES_IngestionConfig.targetMaps('RESIDENTIAL_SALES');
        List<RES_IngestionConfig.TargetMap> product2Maps = RES_IngestionConfig.targetMapsFor('RESIDENTIAL_SALES', 'Product2');
        Test.stopTest();

        Assert.areEqual(maps.size(), cachedMaps.size(), 'Target maps should be cached');
        Assert.isTrue(RES_IngestionConfig.targetMaps('').isEmpty(), 'Blank layout code should return empty list');
        Assert.isNotNull(product2Maps, 'Target maps for Product2 should be returned');
    }

    @IsTest
    static void testConditionMappings() {
        Test.startTest();
        Map<String, RES_IngestionConfig.ConditionMapping> mappings = RES_IngestionConfig.conditionMappings('RESIDENTIAL_SALES');
        Map<String, RES_IngestionConfig.ConditionMapping> cachedMappings = RES_IngestionConfig.conditionMappings('RESIDENTIAL_SALES');
        RES_IngestionConfig.ConditionMapping singleMap = RES_IngestionConfig.conditionMapping('RESIDENTIAL_SALES', 'Y100');
        Test.stopTest();

        Assert.areEqual(mappings.size(), cachedMappings.size(), 'Condition mappings should be cached');
        Assert.isTrue(RES_IngestionConfig.conditionMappings('').isEmpty(), 'Blank layout code should return empty map');
        Assert.isNull(RES_IngestionConfig.conditionMapping('RESIDENTIAL_SALES', ''), 'Blank condition type should return null');
    }

    @IsTest
    static void testSplitListHelper() {
        Test.startTest();
        List<String> emptyResult1 = RES_IngestionConfig.splitList(null);
        List<String> emptyResult2 = RES_IngestionConfig.splitList('');
        List<String> emptyResult3 = RES_IngestionConfig.splitList('   ');
        List<String> parsedResult = RES_IngestionConfig.splitList('Val1; Val2 ; ; Val3 ');
        Test.stopTest();

        Assert.isTrue(emptyResult1.isEmpty(), 'Null string should return empty list');
        Assert.isTrue(emptyResult2.isEmpty(), 'Blank string should return empty list');
        Assert.isTrue(emptyResult3.isEmpty(), 'Whitespace string should return empty list');
        Assert.areEqual(3, parsedResult.size(), 'Should split and trim non-empty values');
        Assert.areEqual('Val1', parsedResult[0]);
        Assert.areEqual('Val2', parsedResult[1]);
        Assert.areEqual('Val3', parsedResult[2]);
    }
}