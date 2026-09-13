/*
 * Class Name  : RES_AttributeBasedAdjRuleDAOLayer
 * Description : DAO layer for AttributeBasedAdjRule object.
 */
public without sharing class RES_AttributeBasedAdjRuleDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'AttributeBasedAdjRule';
    }

    public List<AttributeBasedAdjRule> getRulesByNames(Set<String> wantedRuleNames) {
        if (wantedRuleNames == null || wantedRuleNames.isEmpty()) return new List<AttributeBasedAdjRule>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'wantedRuleNames' => wantedRuleNames };
        String soql = 'SELECT Id, Name FROM AttributeBasedAdjRule WHERE Name IN :wantedRuleNames';
        return (List<AttributeBasedAdjRule>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}