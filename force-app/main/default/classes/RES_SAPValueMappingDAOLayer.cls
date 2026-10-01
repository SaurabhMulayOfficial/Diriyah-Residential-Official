public without sharing class RES_SAPValueMappingDAOLayer extends RES_BaseDAOLayer {
    public RES_SAPValueMappingDAOLayer() {}

    protected override String getSObjectName() {
        return 'RES_SAP_Value_Mapping__mdt';
    }

    public Map<String, Map<String, String>> getAllMappingsAsMap() {
        String soql = 'SELECT DeveloperName, RES_Json_Mapping__c '
                    + 'FROM RES_SAP_Value_Mapping__mdt';
        List<RES_SAP_Value_Mapping__mdt> records = executeQuery(soql, 'ALL_SAP_MAPPINGS', false, null, AccessLevel.SYSTEM_MODE);
        Map<String, Map<String, String>> result = new Map<String, Map<String, String>>();
        for (RES_SAP_Value_Mapping__mdt rec : records) {
            if (String.isBlank(rec.RES_Json_Mapping__c)) {
                result.put(rec.DeveloperName, new Map<String, String>());
                continue;
            }
            try {
                result.put(rec.DeveloperName, (Map<String, String>) JSON.deserialize(rec.RES_Json_Mapping__c, Map<String, String>.class));
            } catch (Exception e) {
                System.debug('### [SAP_Mapping] Failed to deserialize mapping for "' + rec.DeveloperName + '": ' + e.getMessage());
                result.put(rec.DeveloperName, new Map<String, String>());
            }
        }
        return result;
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