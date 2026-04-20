public with sharing class RES_UserAvailabilityController {
    private static final Set<String> ALLOWED_STATUSES = new Set<String>{
        'Available',
        'Offline'
    };

    @AuraEnabled
    public static String updateUserStatus(String newStatus) {
        Id userId = UserInfo.getUserId();
        if (String.isBlank(newStatus) || !ALLOWED_STATUSES.contains(newStatus)) {
            throw new AuraHandledException('Invalid status value.');
        }
        List<RES_Assignment_Rule__c> records = new RES_AssignmentRuleDAO().getRecordByUserId(userId);
        if (records.isEmpty()) {
            throw new AuraHandledException('No Assignment record found for user.');
        }
        for(RES_Assignment_Rule__c r:records){
            r.RES_User_Availability_Status__c = newStatus;
        }
        Database.update(records,true,AccessLevel.SYSTEM_MODE);
        return newStatus;
    }

    @AuraEnabled
    public static string getUserStatus(){
        Id userId = UserInfo.getUserId();
        List<RES_Assignment_Rule__c> records = new RES_AssignmentRuleDAO().getRecordByUserId(userId);
        if (records.isEmpty()) {
            throw new AuraHandledException('No Assignment record found for user.');
        }
        string existingStatus = records[0].RES_User_Availability_Status__c;
        return existingStatus;
    }
}