/**
 * @description Tests for RES_ConditionMappingDAOLayer.
 * @author      Roshan Jambhule
 * @date        2025
 */
@isTest
private class RES_ConditionMappingDAOLayerTest {

    @isTest
    static void testGetAllActive_returnsNonNullList() {
        List<RES_Condition_Mapping__mdt> result = new RES_ConditionMappingDAOLayer().getAllActive();
        Assert.isNotNull(result, 'getAllActive should never return null');
    }

    @isTest
    static void testGetAllActive_returnsListType() {
        Test.startTest();
        List<RES_Condition_Mapping__mdt> result = new RES_ConditionMappingDAOLayer().getAllActive();
        Test.stopTest();
        Assert.isNotNull(result, 'Result must not be null');
        Assert.isTrue(result instanceof List<RES_Condition_Mapping__mdt>, 'Must return correct type');
    }

    @isTest
    static void testGetActiveConditionMappingsByLayoutCode_blankCode_returnsEmpty() {
        List<RES_Condition_Mapping__mdt> result = new RES_ConditionMappingDAOLayer()
            .getActiveConditionMappingsByLayoutCode('');
        Assert.isNotNull(result, 'Result must not be null for blank layout code');
        Assert.isTrue(result.isEmpty(), 'Blank layout code must return empty list');
    }

    @isTest
    static void testGetActiveConditionMappingsByLayoutCode_nullCode_returnsEmpty() {
        List<RES_Condition_Mapping__mdt> result = new RES_ConditionMappingDAOLayer()
            .getActiveConditionMappingsByLayoutCode(null);
        Assert.isNotNull(result, 'Result must not be null for null layout code');
        Assert.isTrue(result.isEmpty(), 'Null layout code must return empty list');
    }

    @isTest
    static void testGetActiveConditionMappingsByLayoutCode_nonExistentCode_returnsEmpty() {
        Test.startTest();
        List<RES_Condition_Mapping__mdt> result = new RES_ConditionMappingDAOLayer()
            .getActiveConditionMappingsByLayoutCode('NONEXISTENT_LAYOUT_XYZ_999');
        Test.stopTest();
        Assert.isNotNull(result, 'Result must not be null for non-existent layout code');
        Assert.isTrue(result.isEmpty(), 'Non-existent layout code must return empty list');
    }

    @isTest
    static void testConstructorInstantiates() {
        Assert.isNotNull(new RES_ConditionMappingDAOLayer(), 'Constructor should succeed');
    }
}
