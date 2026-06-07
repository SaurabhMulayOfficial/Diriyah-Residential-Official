public with sharing class RES_AssignmentWorkloadService {

    public static void runReassignmentProcess(List<RES_Assignment_Workload__c> workloads, Map<Id, RES_Assignment_Workload__c>oldMap){
        List<RES_Lead_Distribution__e> events = new List<RES_Lead_Distribution__e>();

        Set<Id> workloadIds = new Set<Id>();
        for(RES_Assignment_Workload__c aw: workloads){
            RES_Assignment_Workload__c old = oldMap.get(aw.Id);
            if(evaluateChange(aw,old)){
                workloadIds.add(aw.Id);
            }
        }

        List<RES_Assignment_Rule__c> assignmentRules = new RES_AssignmentRuleDAO().getRuleByWorkLoadIds(workloadIds);
        
        Set<String> queueNames = new Set<String>();

        for(RES_Assignment_Rule__c rule: assignmentRules){
            queueNames.add(rule.RES_Assignment_Config__r.RES_Queue__c);
        }

        System.debug('QUEUEs '+ queueNames);

        for(String queueName: queueNames){
            if(!String.isBlank(queueName)){
                events.add(new RES_Lead_Distribution__e(RES_Queue__c = queueName));
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

    private static boolean evaluateChange(RES_Assignment_Workload__c curr, RES_Assignment_Workload__c old){
        if(curr.RES_Capacity__c > old.RES_Capacity__c  || curr.RES_Active_Lead_Count__c < old.RES_Active_Lead_Count__c){
            return true;
        }
        return false;
    }
}