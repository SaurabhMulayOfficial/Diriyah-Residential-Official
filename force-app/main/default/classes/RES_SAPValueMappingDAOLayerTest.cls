/**
 * @description Tests for RES_SAPValueMappingDAOLayer — JSON-deserialization-based CMT accessor.
 * @author      Roshan Jambhule
 * @date        2025
 */
@isTest
private class RES_SAPValueMappingDAOLayerTest {

    @isTest
    static void testGetAllMappingsAsMap_returnsNonNullMap() {
        Map<String, Map<String, String>> result = new RES_SAPValueMappingDAOLayer()
            .getAllMappingsAsMap();
        Assert.isNotNull(result, 'getAllMappingsAsMap should never return null');
    }

    @isTest
    static void testGetAllMappingsAsMap_unitStatusKeyPresent() {
        Map<String, Map<String, String>> result = new RES_SAPValueMappingDAOLayer()
            .getAllMappingsAsMap();
        Assert.isTrue(result.containsKey('Unit_Status'), 'Unit_Status key should be present');
        Assert.isNotNull(result.get('Unit_Status'), 'Unit_Status map should not be null');
    }

    @isTest
    static void testGetAllMappingsAsMap_fixtureKeyPresent() {
        Map<String, Map<String, String>> result = new RES_SAPValueMappingDAOLayer()
            .getAllMappingsAsMap();
        Assert.isTrue(result.containsKey('Fixture_Boolean'), 'Fixture_Boolean key should be present');
    }

    @isTest
    static void testConstructorInstantiates() {
        Assert.isNotNull(new RES_SAPValueMappingDAOLayer(), 'Constructor should succeed');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getMappingByObjectsAndFields
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void getMappingByObjectsAndFields_emptyObjectNames_returnsEmptyMap() {
        Map<String, Map<String, String>> result = new RES_SAPValueMappingDAOLayer()
            .getMappingByObjectsAndFields(new Set<String>(), new Set<String>{ 'Contract_Status' });
        Assert.isNotNull(result, 'Result must not be null for empty objectNames.');
        Assert.isTrue(result.isEmpty(), 'Result must be empty when objectNames is empty.');
    }

    @isTest
    static void getMappingByObjectsAndFields_emptyFieldNames_returnsEmptyMap() {
        Map<String, Map<String, String>> result = new RES_SAPValueMappingDAOLayer()
            .getMappingByObjectsAndFields(new Set<String>{ 'Contract' }, new Set<String>());
        Assert.isNotNull(result, 'Result must not be null for empty fieldNames.');
        Assert.isTrue(result.isEmpty(), 'Result must be empty when fieldNames is empty.');
    }

    @isTest
    static void getMappingByObjectsAndFields_nullObjectNames_returnsEmptyMap() {
        Map<String, Map<String, String>> result = new RES_SAPValueMappingDAOLayer()
            .getMappingByObjectsAndFields(null, new Set<String>{ 'Contract_Status' });
        Assert.isNotNull(result, 'Result must not be null for null objectNames.');
        Assert.isTrue(result.isEmpty(), 'Result must be empty when objectNames is null.');
    }

    @isTest
    static void getMappingByObjectsAndFields_validInputs_returnsMap() {
        Map<String, Map<String, String>> result = new RES_SAPValueMappingDAOLayer()
            .getMappingByObjectsAndFields(
                new Set<String>{ 'Product2' },
                new Set<String>{ 'RES_Unit_Status__c' }
            );
        Assert.isNotNull(result, 'Result must not be null for valid inputs.');
        Assert.isFalse(result.isEmpty(), 'Unit_Status MDT record must be found for Product2/RES_Unit_Status__c.');
    }

    @isTest
    static void getMappingByObjectsAndFields_nonExistentCategory_returnsEmptyMap() {
        Map<String, Map<String, String>> result = new RES_SAPValueMappingDAOLayer()
            .getMappingByObjectsAndFields(
                new Set<String>{ 'NONEXISTENT_OBJECT_XYZ' },
                new Set<String>{ 'NONEXISTENT_FIELD_XYZ' }
            );
        Assert.isNotNull(result, 'Result must not be null for non-existent category.');
        Assert.isTrue(result.isEmpty(), 'Result must be empty when no CMT record matches.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // deserializeJsonMapping — covers blank JSON and malformed JSON paths
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void deserializeJsonMapping_blankJson_returnsEmptyMap() {
        Map<String, String> result = RES_SAPValueMappingDAOLayer.deserializeJsonMapping('Test_Key', '');
        Assert.isNotNull(result, 'Must return empty map, never null');
        Assert.isTrue(result.isEmpty(), 'Blank JSON must return empty map');
    }

    @isTest
    static void deserializeJsonMapping_nullJson_returnsEmptyMap() {
        Map<String, String> result = RES_SAPValueMappingDAOLayer.deserializeJsonMapping('Test_Key', null);
        Assert.isNotNull(result, 'Must return empty map, never null');
        Assert.isTrue(result.isEmpty(), 'Null JSON must return empty map');
    }

    @isTest
    static void deserializeJsonMapping_malformedJson_returnsEmptyMap() {
        Map<String, String> result = RES_SAPValueMappingDAOLayer.deserializeJsonMapping('Test_Key', '{not valid json!!!}');
        Assert.isNotNull(result, 'Must return empty map on parse failure');
        Assert.isTrue(result.isEmpty(), 'Malformed JSON must return empty map');
    }

    @isTest
    static void deserializeJsonMapping_validJson_returnsPopulatedMap() {
        Map<String, String> result = RES_SAPValueMappingDAOLayer.deserializeJsonMapping('Test_Key', '{"Available":"E0010","Sold":"E0011"}');
        Assert.isNotNull(result, 'Must return populated map');
        Assert.areEqual('E0010', result.get('Available'), 'Available must map to E0010');
        Assert.areEqual('E0011', result.get('Sold'), 'Sold must map to E0011');
    }
}
