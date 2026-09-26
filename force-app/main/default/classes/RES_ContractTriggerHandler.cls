public with sharing class RES_ContractTriggerHandler extends RES_BaseTriggerHandler {
    public RES_ContractTriggerHandler() {}

    @TestVisible
    protected override void afterInsert() {
        //RES_AccountServices.handleContractAccountSync((List<Contract>) Trigger.new);
    }

    @TestVisible
    protected override void afterUpdate() {
    }
}
