/**
 * Controller class for Lead Creation business logic
 * Called in lwc resLeadCreateModal
 */
public with sharing class RES_LeadCreateController {

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getLeadRecordTypes() {
        List<Map<String, String>> recordTypes = new List<Map<String, String>>();
        List<RecordType> rtList = [
            SELECT Id, Name, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Lead'
            AND IsActive = true
            ORDER BY Name
        ];

        for (RecordType rt : rtList) {
            Map<String, String> rtMap = new Map<String, String>();
            rtMap.put('id', rt.Id);
            rtMap.put('name', rt.Name);
            rtMap.put('developerName', rt.DeveloperName);
            recordTypes.add(rtMap);
        }

        return recordTypes;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getRecordTypeById(String recordTypeId) {
        Map<String, String> result = new Map<String, String>();

        if (String.isBlank(recordTypeId)) {
            return result;
        }

        List<RecordType> rtList = [
            SELECT Id, Name, DeveloperName
            FROM RecordType
            WHERE Id = :recordTypeId
            AND SObjectType = 'Lead'
            AND IsActive = true
            LIMIT 1
        ];

        if (!rtList.isEmpty()) {
            result.put('id', rtList[0].Id);
            result.put('name', rtList[0].Name);
            result.put('developerName', rtList[0].DeveloperName);
        }

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPicklistValues(String fieldApiName) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        Schema.SObjectType leadType = Schema.getGlobalDescribe().get('Lead');
        Schema.DescribeSObjectResult leadDescribe = leadType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = leadDescribe.fields.getMap();

        if (fieldMap.containsKey(fieldApiName)) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();

            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                if (entry.isActive()) {
                    Map<String, String> option = new Map<String, String>();
                    option.put('label', entry.getLabel());
                    option.put('value', entry.getValue());
                    options.add(option);
                }
            }
        }

        return options;
    }

    @AuraEnabled(cacheable=true)
    public static String getCurrentUserRoleName() {
        List<User> users = [
            SELECT UserRole.DeveloperName
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (users.isEmpty() || users[0].UserRole == null) {
            return null;
        }

        return users[0].UserRole.DeveloperName;
    }

    @AuraEnabled(cacheable=true)
    public static Boolean isSystemAdmin() {
        List<Profile> profiles = [
            SELECT Name
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
            LIMIT 1
        ];

        return !profiles.isEmpty() && profiles[0].Name == System.Label.RES_Admin_Profile;
    }

    @AuraEnabled(cacheable=true)
    public static Boolean hasLeadSourceAccessByRole() {
        List<User> users = [
            SELECT UserRole.DeveloperName
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (users.isEmpty() || users[0].UserRole == null) {
            return false;
        }

        List<RES_Role_Field_Access__mdt> accessRecords = [
            SELECT Id
            FROM RES_Role_Field_Access__mdt
            WHERE Role_API__c = :users[0].UserRole.DeveloperName
            AND Field_API__c = 'LeadSource'
            LIMIT 1
        ];

        return !accessRecords.isEmpty();
    }

    @AuraEnabled
    public static Lead createLead(Map<String, Object> fieldValues, String recordTypeId) {
        Lead newLead = new Lead();
        newLead.RecordTypeId = recordTypeId;

        Schema.SObjectType leadType = Schema.getGlobalDescribe().get('Lead');
        Map<String, Schema.SObjectField> fieldMap = leadType.getDescribe().fields.getMap();

        for (String fieldName : fieldValues.keySet()) {
            if (
                fieldMap.containsKey(fieldName)
                && fieldValues.get(fieldName) != null
                && fieldValues.get(fieldName) != ''
            ) {
                newLead.put(fieldName, fieldValues.get(fieldName));
            }
        }

        insert newLead;

        return [
            SELECT Id, Name, FirstName, LastName
            FROM Lead
            WHERE Id = :newLead.Id
            LIMIT 1
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getFilteredLeadSourceValues() {
        Set<String> allowedValues = new Set<String>{'Z02', 'Z03', 'Z04', 'Z05', 'Z12', 'Cityscape'};
        List<Map<String, String>> options = new List<Map<String, String>>();

        Schema.DescribeFieldResult fieldDescribe = Lead.LeadSource.getDescribe();

        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive() && allowedValues.contains(entry.getValue())) {
                Map<String, String> option = new Map<String, String>();
                option.put('label', entry.getLabel());
                option.put('value', entry.getValue());
                options.add(option);
            }
        }

        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getFilteredIdentificationTypeValues() {
        Set<String> allowedValues = new Set<String>{'ZIT01', 'ZIT02', 'ZIT03', 'GCC ID'};
        List<Map<String, String>> options = new List<Map<String, String>>();

        Schema.DescribeFieldResult fieldDescribe = Lead.RES_Identification_Type__c.getDescribe();

        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive() && allowedValues.contains(entry.getValue())) {
                Map<String, String> option = new Map<String, String>();
                option.put('label', entry.getLabel());
                option.put('value', entry.getValue());
                options.add(option);
            }
        }

        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCityscapeYearValues() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        Schema.DescribeFieldResult fieldDescribe = Lead.RES_Cityscape_Year__c.getDescribe();

        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                Map<String, String> option = new Map<String, String>();
                option.put('label', entry.getLabel());
                option.put('value', entry.getValue());
                options.add(option);
            }
        }

        return options;
    }
}