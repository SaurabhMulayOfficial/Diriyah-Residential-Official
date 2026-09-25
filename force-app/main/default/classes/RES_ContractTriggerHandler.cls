public with sharing class RES_ContractTriggerHandler extends RES_BaseTriggerHandler {
    public RES_ContractTriggerHandler() {}

    protected override void afterInsert(){
        //RES_AccountServices.handleContractAccountSync((List<Contract>) Trigger.new);
    }

    protected override void afterUpdate(){
    }
    
}