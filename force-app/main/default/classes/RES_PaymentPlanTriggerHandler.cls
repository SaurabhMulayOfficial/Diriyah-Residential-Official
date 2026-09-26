public with sharing class RES_PaymentPlanTriggerHandler extends RES_BaseTriggerHandler {
    public RES_PaymentPlanTriggerHandler() {}

    protected override void afterInsert(){
        RES_PaymentPlanServices.syncPaymentPlans((List<RES_Payment_Plan__c>) Trigger.new, null);
    }

    protected override void afterUpdate() {
        RES_PaymentPlanServices.syncPaymentPlans((List<RES_Payment_Plan__c>) Trigger.new, (Map<Id, RES_Payment_Plan__c>) Trigger.oldMap);
    }
}