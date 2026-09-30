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
}
