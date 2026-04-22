public with sharing class RES_UserAvailabilityController {

    @AuraEnabled(cacheable=true)
    public static Map<String,Object> getUserStatusData() {
        Id userId = UserInfo.getUserId();
        List<RES_Assignment_Rule__c> records =
            new RES_AssignmentRuleDAO().getRecordByUserId(userId);

        if(records.isEmpty()){
            throw new AuraHandledException('No Assignment record found for user.');
        }

        String currentStatus = records[0].RES_User_Availability_Status__c;
        List<String> values = new List<String>();
        Schema.DescribeFieldResult fieldInfo =
            RES_Assignment_Rule__c.RES_User_Availability_Status__c.getDescribe();
        for(Schema.PicklistEntry pe : fieldInfo.getPicklistValues()){
            if(pe.isActive()){
                values.add(pe.getValue());
            }
        }

        Map<String,Object> result = new Map<String,Object>();
        result.put('currentStatus', currentStatus);
        result.put('picklistValues', values);
        return result;
    }

    @AuraEnabled
    public static String updateUserStatus(String newStatus) {
        Id userId = UserInfo.getUserId();
        List<RES_Assignment_Rule__c> records =
            new RES_AssignmentRuleDAO().getRecordByUserId(userId);
        if(records.isEmpty()){
            throw new AuraHandledException('No Assignment record found for user.');
        }

        for(RES_Assignment_Rule__c rec : records){
            rec.RES_User_Availability_Status__c = newStatus;
        }
        update records;
        return newStatus;
    }
}