public with sharing class RES_InstallmentTriggerHandler extends RES_BaseTriggerHandler {
    public RES_InstallmentTriggerHandler() {}

    protected override void afterInsert(){
        RES_InstallmentServices.syncInstallments((List<RES_Installment__c>) Trigger.new, null);
    }
    
    protected override void afterUpdate(){
        RES_InstallmentServices.syncInstallments((List<RES_Installment__c>) Trigger.new, (Map<Id,RES_Installment__c>) Trigger.oldMap);
    }
}