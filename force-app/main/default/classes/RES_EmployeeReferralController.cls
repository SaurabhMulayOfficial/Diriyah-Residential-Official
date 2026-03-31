
public with sharing class RES_EmployeeReferralController {
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Id> getLeadRecordTypeIds() {
        Map<String, Id> rtMap = new Map<String, Id>();
        try {
            // Fetching IDs dynamically using Developer Names
            rtMap.put('Individual', Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
                .get('RES_Individual').getRecordTypeId());
            rtMap.put('Company', Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
                .get('RES_Company').getRecordTypeId());
        } catch (Exception e) {
            throw new AuraHandledException('Record Types not found: ' + e.getMessage());
        }
        return rtMap;
    }
}