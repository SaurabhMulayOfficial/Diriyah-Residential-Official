/*
 * Class Name  : RES_ConditionMappingDAOLayer
 * Description : DAO layer for RES_Condition_Mapping__mdt metadata object.
 */
public without sharing class RES_ConditionMappingDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'RES_Condition_Mapping__mdt';
    }

    public List<RES_Condition_Mapping__mdt> getActiveConditionMappingsByLayoutCode(String layoutCode) {
        if (String.isBlank(layoutCode)) return new List<RES_Condition_Mapping__mdt>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'layoutCode' => layoutCode };
        String soql = 'SELECT RES_Condition_Type__c, RES_Handling__c, RES_Attribute_Name__c, ' +
                      'RES_Attribute_Data_Type__c, RES_Selling_Model_Type__c, RES_Pricing_Term__c, ' +
                      'RES_Pricing_Term_Unit__c, RES_Is_Primary__c, RES_Selector_Value__c, RES_Adjustment_Type__c ' +
                      'FROM RES_Condition_Mapping__mdt ' +
                      'WHERE RES_Is_Active__c = true AND RES_Layout__r.RES_Layout_Code__c = :layoutCode ' +
                      'ORDER BY RES_Sequence__c NULLS LAST';
        return (List<RES_Condition_Mapping__mdt>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}