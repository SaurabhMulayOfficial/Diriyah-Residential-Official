/*
 * Class Name  : RES_AttributeAdjustmentConditionDAOLayer
 * Description : DAO layer for AttributeAdjustmentCondition object.
 */
public without sharing class RES_AttributeAdjustmentConditionDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'AttributeAdjustmentCondition';
    }

    public List<AttributeAdjustmentCondition> getConditionsByRuleIds(Set<Id> ruleIds) {
        if (ruleIds == null || ruleIds.isEmpty()) return new List<AttributeAdjustmentCondition>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'ruleIds' => ruleIds };
        String soql = 'SELECT AttributeBasedAdjRuleId FROM AttributeAdjustmentCondition WHERE AttributeBasedAdjRuleId IN :ruleIds';
        return (List<AttributeAdjustmentCondition>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}