public without sharing class RES_SAPValueMappingDAOLayer extends RES_BaseDAOLayer {
    public RES_SAPValueMappingDAOLayer() {}

    protected override String getSObjectName() {
        return 'RES_SAP_Value_Mapping__mdt';
    }

    private List<RES_SAP_Value_Mapping__mdt> getMappingsByCategory(String category) {
        Map<String, Object> bindVars = new Map<String, Object>{ 'category' => category };
        String soql = 'SELECT RES_Category__c, RES_Json_Mapping__c, RES_Json_False_Mapping__c, RES_Is_Active__c '
                    + 'FROM RES_SAP_Value_Mapping__mdt '
                    + 'WHERE RES_Category__c = :category AND RES_Is_Active__c = true '
                    + 'LIMIT 1';
        return executeQuery(soql, category, true, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public Map<String, String> getMappingAsMap(String category) {
        List<RES_SAP_Value_Mapping__mdt> records = getMappingsByCategory(category);
        if (records.isEmpty() || String.isBlank(records[0].RES_Json_Mapping__c)) {
            return new Map<String, String>();
        }
        try {
            return (Map<String, String>) JSON.deserialize(records[0].RES_Json_Mapping__c, Map<String, String>.class);
        } catch (Exception e) {
            System.debug('### [SAP_Mapping] Failed to deserialize mapping for "' + category + '": ' + e.getMessage());
            return new Map<String, String>();
        }
    }

    public Map<String, String> getFalseMappingAsMap(String category) {
        List<RES_SAP_Value_Mapping__mdt> records = getMappingsByCategory(category);
        if (records.isEmpty() || String.isBlank(records[0].RES_Json_False_Mapping__c)) {
            return new Map<String, String>();
        }
        try {
            return (Map<String, String>) JSON.deserialize(records[0].RES_Json_False_Mapping__c, Map<String, String>.class);
        } catch (Exception e) {
            System.debug('### [SAP_Mapping] Failed to deserialize false mapping for "' + category + '": ' + e.getMessage());
            return new Map<String, String>();
        }
    }
}
