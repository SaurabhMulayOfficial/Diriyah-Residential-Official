public with sharing class RES_AssignmentWorkloadHandler extends RES_BaseTriggerHandler {
    protected override void afterUpdate() {
        RES_AssignmentWorkloadService.runReassignmentProcess((List<RES_Assignment_Workload__c>) Trigger.new, (Map<Id, RES_Assignment_Workload__c>)Trigger.oldMap);
    }
}