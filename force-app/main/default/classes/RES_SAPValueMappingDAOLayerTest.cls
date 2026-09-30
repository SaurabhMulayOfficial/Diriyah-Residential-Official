/**
 * @description Tests for RES_SAPValueMappingDAOLayer — JSON-deserialization-based CMT accessor.
 * @author      Roshan Jambhule
 * @date        2025
 */
@isTest
private class RES_SAPValueMappingDAOLayerTest {

    @isTest
    static void testGetMappingAsMap_returnsEmptyWhenCategoryMissing() {
        Map<String, String> result = new RES_SAPValueMappingDAOLayer()
            .getMappingAsMap('NONEXISTENT_CATEGORY_XYZ');
        Assert.isNotNull(result, 'Should return an empty map, not null');
        Assert.isTrue(result.isEmpty(), 'Should be empty when no matching CMT record exists');
    }

    @isTest
    static void testGetFalseMappingAsMap_returnsEmptyWhenCategoryMissing() {
        Map<String, String> result = new RES_SAPValueMappingDAOLayer()
            .getFalseMappingAsMap('NONEXISTENT_CATEGORY_XYZ');
        Assert.isNotNull(result, 'Should return an empty map, not null');
        Assert.isTrue(result.isEmpty(), 'Should be empty when no matching CMT record exists');
    }

    @isTest
    static void testGetMappingAsMap_returnsValuesForDeployedCategory() {
        Map<String, String> result = new RES_SAPValueMappingDAOLayer()
            .getMappingAsMap('Unit_Status');
        Assert.isNotNull(result, 'Unit_Status mapping should not be null');
    }

    @isTest
    static void testGetFalseMappingAsMap_returnsValuesForDeployedCategory() {
        Map<String, String> result = new RES_SAPValueMappingDAOLayer()
            .getFalseMappingAsMap('Fixture_Boolean');
        Assert.isNotNull(result, 'Fixture_Boolean false mapping should not be null');
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
                new Set<String>{ 'Contract' },
                new Set<String>{ 'Contract_Status' }
            );
        Assert.isNotNull(result, 'Result must not be null for valid inputs.');
        // The map may or may not have entries depending on deployed CMT records
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
}
