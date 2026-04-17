public with sharing class RES_UserAvailabilityController {
    private static final Set<String> ALLOWED_STATUSES = new Set<String>{
        'Available',
        'Offline'
    };

    @AuraEnabled
    public static String updateUserStatus(String newStatus) {

        Id userId = UserInfo.getUserId();

        // Validate input
        if (String.isBlank(newStatus) || !ALLOWED_STATUSES.contains(newStatus)) {
            throw new AuraHandledException('Invalid status value.');
        }

        // Query record
        List<RES_Assignment_Rule__c> records = [
            SELECT Id, RES_User_Availability_Status__c
            FROM RES_Assignment_Rule__c
            WHERE RES_User__c = :userId
            LIMIT 1
        ];

        if (records.isEmpty()) {
            throw new AuraHandledException('No Assignment record found for user.');
        }

        RES_Assignment_Rule__c rec = records[0];

        // FLS Check
        if (!Schema.sObjectType.RES_Assignment_Rule__c.fields
            .RES_User_Availability_Status__c.isUpdateable()) {
            throw new AuraHandledException('No permission to update status.');
        }

        rec.RES_User_Availability_Status__c = newStatus;

        update rec;

        // OPTIONAL: Call your reassignment logic (Only if needed when user becomes available)
        if (newStatus == 'Available') {
           // RES_ReassignmentLogicHandler.handleUserAvailable(userId);
        }

        return newStatus;
    }

    @AuraEnabled(cacheable=true)
    public static String getUserStatus() {
        Id userId = UserInfo.getUserId();

        List<RES_Assignment_Rule__c> records = [
            SELECT RES_User_Availability_Status__c
            FROM RES_Assignment_Rule__c
            WHERE RES_User__c = :userId
            LIMIT 1
        ];

        if (records.isEmpty()) {
            return 'Offline';
        }

        return records[0].RES_User_Availability_Status__c;
    }
}