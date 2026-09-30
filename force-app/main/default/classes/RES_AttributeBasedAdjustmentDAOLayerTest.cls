/**
 * @description Tests for RES_AttributeBasedAdjustmentDAOLayer.
 * @author      Roshan Jambhule
 * @date        2025
 */
@isTest
private class RES_AttributeBasedAdjustmentDAOLayerTest {

    @isTest
    static void testGetAdjustmentsByRuleIdsNullAndEmptyReturnEmpty() {
        RES_AttributeBasedAdjustmentDAOLayer dao = new RES_AttributeBasedAdjustmentDAOLayer();
        Assert.areEqual(0, dao.getAdjustmentsByRuleIds(null).size(), 'Null ruleIds must return empty list');
        Assert.areEqual(0, dao.getAdjustmentsByRuleIds(new Set<Id>()).size(), 'Empty ruleIds must return empty list');
    }

    @isTest
    static void testGetByProductIdsNullAndEmptyReturnEmpty() {
        RES_AttributeBasedAdjustmentDAOLayer dao = new RES_AttributeBasedAdjustmentDAOLayer();
        Assert.areEqual(0, dao.getByProductIds(null).size(), 'Null productIds must return empty list');
        Assert.areEqual(0, dao.getByProductIds(new Set<Id>()).size(), 'Empty productIds must return empty list');
    }

    @isTest
    static void testGetAdjustmentsByRuleIdsExecutesQuery() {
        // Insert a rule to get a real Id — query will return empty but the SOQL path is covered
        AttributeBasedAdjRule rule = new AttributeBasedAdjRule(Name = 'DAO-Layer-Test-Rule');
        insert rule;

        Test.startTest();
        List<AttributeBasedAdjustment> results =
            new RES_AttributeBasedAdjustmentDAOLayer().getAdjustmentsByRuleIds(new Set<Id>{ rule.Id });
        Test.stopTest();

        Assert.isNotNull(results, 'Result list must not be null');
    }

    @isTest
    static void testGetByProductIdsExecutesQuery() {
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId = UserInfo.getOrganizationId(), RES_Triggers_Off__c = true
        );
        upsert cfg;
        Product2 p = new Product2(Name = 'DAO-Layer-Test-Product', IsActive = true);
        insert p;
        cfg.RES_Triggers_Off__c = false;
        update cfg;

        Test.startTest();
        List<AttributeBasedAdjustment> results =
            new RES_AttributeBasedAdjustmentDAOLayer().getByProductIds(new Set<Id>{ p.Id });
        Test.stopTest();

        Assert.isNotNull(results, 'Result list must not be null');
    }
}
