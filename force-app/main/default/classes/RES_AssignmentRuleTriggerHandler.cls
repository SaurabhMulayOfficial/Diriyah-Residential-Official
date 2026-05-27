public with sharing class RES_AssignmentRuleTriggerHandler extends RES_BaseTriggerHandler {
    public RES_AssignmentRuleTriggerHandler() {}
    protected override void afterInsert(){
        RES_AssignmentRuleService.publishLeadDistributionEvents((List<RES_Assignment_Rule__c>)Trigger.new, null);
    }

    protected override void afterUpdate() {
        RES_AssignmentRuleService.publishLeadDistributionEvents((List<RES_Assignment_Rule__c>)Trigger.new, (Map<Id, RES_Assignment_Rule__c>) Trigger.oldMap);
    }
}