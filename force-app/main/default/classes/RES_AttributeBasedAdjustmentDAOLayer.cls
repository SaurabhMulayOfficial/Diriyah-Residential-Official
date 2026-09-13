/*
 * Class Name  : RES_AttributeBasedAdjustmentDAOLayer
 * Description : DAO layer for AttributeBasedAdjustment object.
 */
public without sharing class RES_AttributeBasedAdjustmentDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'AttributeBasedAdjustment';
    }

    public List<AttributeBasedAdjustment> getAdjustmentsByRuleIds(Set<Id> ruleIds) {
        if (ruleIds == null || ruleIds.isEmpty()) return new List<AttributeBasedAdjustment>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'ruleIds' => ruleIds };
        String soql = 'SELECT Id, AttributeBasedAdjRuleId, AdjustmentValue, AdjustmentType, EffectiveFrom, EffectiveTo ' +
                      'FROM AttributeBasedAdjustment WHERE AttributeBasedAdjRuleId IN :ruleIds';
        return (List<AttributeBasedAdjustment>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}