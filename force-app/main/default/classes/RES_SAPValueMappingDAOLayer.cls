public without sharing class RES_SAPValueMappingDAOLayer extends RES_BaseDAOLayer {
    public RES_SAPValueMappingDAOLayer() {}

    protected override String getSObjectName() {
        return 'RES_SAP_Value_Mapping__mdt';
    }

    private List<RES_SAP_Value_Mapping__mdt> getMappingsByCategory(String category) {
        Map<String, Object> bindVars = new Map<String, Object>{ 'category' => category };
        String soql = 'SELECT RES_Field_Name__c, RES_Object_Name__c, RES_Json_Mapping__c '
                    + 'FROM RES_SAP_Value_Mapping__mdt '
                    + 'WHERE DeveloperName = :category '
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
        return getMappingAsMap(category + '_False');
    }


    public Map<String, Map<String, String>> getMappingByObjectsAndFields(Set<String> objectNames, Set<String> fieldNames){
        Map<String, Map<String, String>> result = new Map<String, Map<String, String>>();
        if (objectNames == null || objectNames.isEmpty() || fieldNames == null || fieldNames.isEmpty()) {
            return result;
        }
        String cacheKey = String.join(new List<String>(objectNames), '_') + '_' + String.join(new List<String>(fieldNames), '_');
        Map<String, Object> bindVars = new Map<String, Object>{
            'objectNames' => objectNames,
            'fieldNames'  => fieldNames
        };
        
        String soql = 'SELECT RES_Object_Name__c, RES_Field_Name__c, RES_Json_Mapping__c '
                    + 'FROM RES_SAP_Value_Mapping__mdt '
                    + 'WHERE RES_Object_Name__c IN :objectNames '
                    + 'AND RES_Field_Name__c IN :fieldNames';

        List<RES_SAP_Value_Mapping__mdt> records = (List<RES_SAP_Value_Mapping__mdt>) executeQuery(soql, cacheKey, true, bindVars, AccessLevel.SYSTEM_MODE);
        for (RES_SAP_Value_Mapping__mdt rec : records) {
            String key = rec.RES_Object_Name__c + rec.RES_Field_Name__c;
            Map<String, String> mapping = new Map<String, String>();
            if (String.isNotBlank(rec.RES_Json_Mapping__c)) {
                try {
                    mapping = (Map<String, String>) JSON.deserialize(rec.RES_Json_Mapping__c, Map<String, String>.class);
                } catch (Exception e) {
                    System.debug('### [SAP_Mapping] Failed to deserialize mapping for "' + key + '": ' + e.getMessage());
                }
            }
            result.put(key, mapping);
        }
        return result;
    }
}