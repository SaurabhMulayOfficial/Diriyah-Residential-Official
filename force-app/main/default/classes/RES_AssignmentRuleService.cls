public with sharing class RES_AssignmentRuleService {
    public RES_AssignmentRuleService() {}

    public static void publishLeadDistributionEvents(List<RES_Assignment_Rule__c> assignmentRules, Map<id, RES_Assignment_Rule__c> oldmap){
        List<RES_Lead_Distribution__e> events = new List<RES_Lead_Distribution__e>();
        Set<Id> configIds = new Set<Id>();

        for(RES_Assignment_Rule__c rule: assignmentRules){
            configIds.add(rule.RES_Assignment_Config__c);
        }

        List<RES_Assignment_Config__c> configList = new RES_AssignmentConfigDAO().getConfigById(configIds);
        Map<Id,String> queueMapping = new Map<Id,String>();

        for(RES_Assignment_Config__c config: configList){
            queueMapping.put(config.Id, config.RES_Queue__c);
        }

        for(RES_Assignment_Rule__c rule: assignmentRules){
            if(oldmap == null){
                if(rule.RES_User_Availability_Status__c == 'Available'){
                    events.add(new RES_Lead_Distribution__e(RES_Queue__c = queueMapping.get(rule.RES_Assignment_Config__c)));
                }
            }else{
                RES_Assignment_Rule__c old = oldmap.get(rule.Id);
                if(evaluateRule(rule, old)){
                    events.add(new RES_Lead_Distribution__e(RES_Queue__c = queueMapping.get(rule.RES_Assignment_Config__c)));
                }
            }
        }

        if(events.isEmpty())return;

        try{
            EventBus.publish(events);
        }
        Catch(Exception e){
            System.debug('Failed to publish events ' + e.getMessage());
        }
    }

    public static Boolean evaluateRule(RES_Assignment_Rule__c curr, RES_Assignment_Rule__c old){
        if(curr.RES_Active_Lead_Count__c < old.RES_Active_Lead_Count__c ||  curr.RES_Capacity__c > old.RES_Capacity__c || (curr.RES_User_Availability_Status__c == 'Available' && old.RES_User_Availability_Status__c != 'Available')){
            return true;
        }
        return false;
    }

}