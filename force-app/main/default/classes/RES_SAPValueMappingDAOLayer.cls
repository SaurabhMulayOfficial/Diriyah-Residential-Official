public without sharing class RES_SAPValueMappingDAOLayer extends RES_BaseDAOLayer {
    public RES_SAPValueMappingDAOLayer() {}

    protected override String getSObjectName() {
        return 'RES_SAP_Value_Mapping__mdt';
    }

    public List<RES_SAP_Value_Mapping__mdt> getMappingsByCategory(String category) {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('category', category);
        String soql = 'SELECT DeveloperName, RES_Category__c, RES_SF_Field__c, RES_SF_Value__c, RES_SAP_Value__c, RES_SAP_False_Value__c, RES_Sequence__c, RES_Is_Active__c ' +
                      'FROM RES_SAP_Value_Mapping__mdt ' +
                      'WHERE RES_Category__c = :category AND RES_Is_Active__c = true ' +
                      'ORDER BY RES_Sequence__c ASC NULLS LAST';
        return executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public List<RES_SAP_Value_Mapping__mdt> getAllActiveMappings() {
        String soql = 'SELECT DeveloperName, RES_Category__c, RES_SF_Field__c, RES_SF_Value__c, RES_SAP_Value__c, RES_SAP_False_Value__c, RES_Sequence__c, RES_Is_Active__c ' +
                      'FROM RES_SAP_Value_Mapping__mdt ' +
                      'WHERE RES_Is_Active__c = true ' +
                      'ORDER BY RES_Category__c ASC, RES_Sequence__c ASC NULLS LAST';
        return executeQuery(soql, 'ALL_ACTIVE', true, new Map<String, Object>(), AccessLevel.SYSTEM_MODE);
    }
}
