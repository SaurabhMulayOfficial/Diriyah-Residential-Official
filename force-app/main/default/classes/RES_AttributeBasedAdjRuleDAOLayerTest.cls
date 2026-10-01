/**
 * @description Tests for RES_AttributeBasedAdjRuleDAOLayer.
 * @author      Roshan Jambhule
 * @date        2025
 */
@isTest
private class RES_AttributeBasedAdjRuleDAOLayerTest {

    @isTest
    static void testGetRulesByNames_nullInput_returnsEmpty() {
        List<AttributeBasedAdjRule> result = new RES_AttributeBasedAdjRuleDAOLayer().getRulesByNames(null);
        Assert.isNotNull(result, 'Result must not be null');
        Assert.isTrue(result.isEmpty(), 'Null input must return empty list');
    }

    @isTest
    static void testGetRulesByNames_emptyInput_returnsEmpty() {
        List<AttributeBasedAdjRule> result = new RES_AttributeBasedAdjRuleDAOLayer().getRulesByNames(new Set<String>());
        Assert.isNotNull(result, 'Result must not be null');
        Assert.isTrue(result.isEmpty(), 'Empty set must return empty list');
    }

    @isTest
    static void testGetRulesByNames_validName_returnsRecord() {
        AttributeBasedAdjRule rule = new AttributeBasedAdjRule(Name = 'Test Coverage Rule ABC');
        insert rule;
        Test.startTest();
        List<AttributeBasedAdjRule> result = new RES_AttributeBasedAdjRuleDAOLayer().getRulesByNames(new Set<String>{ 'Test Coverage Rule ABC' });
        Test.stopTest();
        Assert.isNotNull(result, 'Result must not be null');
        Assert.areEqual(1, result.size(), 'Must return 1 matching rule');
    }

    @isTest
    static void testGetRulesByIds_nullInput_returnsEmpty() {
        List<AttributeBasedAdjRule> result = new RES_AttributeBasedAdjRuleDAOLayer().getRulesByIds(null);
        Assert.isNotNull(result, 'Result must not be null');
        Assert.isTrue(result.isEmpty(), 'Null input must return empty list');
    }

    @isTest
    static void testGetRulesByIds_emptyInput_returnsEmpty() {
        List<AttributeBasedAdjRule> result = new RES_AttributeBasedAdjRuleDAOLayer().getRulesByIds(new Set<Id>());
        Assert.isNotNull(result, 'Result must not be null');
        Assert.isTrue(result.isEmpty(), 'Empty set must return empty list');
    }

    @isTest
    static void testGetRulesByIds_validId_returnsRecord() {
        AttributeBasedAdjRule rule = new AttributeBasedAdjRule(Name = 'Test Coverage Rule ById');
        insert rule;
        Test.startTest();
        List<AttributeBasedAdjRule> result = new RES_AttributeBasedAdjRuleDAOLayer().getRulesByIds(new Set<Id>{ rule.Id });
        Test.stopTest();
        Assert.isNotNull(result, 'Result must not be null');
        Assert.areEqual(1, result.size(), 'Must return 1 matching rule');
        Assert.areEqual(rule.Id, result[0].Id, 'Returned rule Id must match');
    }

}
