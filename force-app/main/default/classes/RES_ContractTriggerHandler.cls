public with sharing class RES_ContractTriggerHandler extends RES_BaseTriggerHandler {
    public RES_ContractTriggerHandler() {}

  protected override void afterInsert() {
        handleAfterInsert((List<Contract>) Trigger.new);
    }

    protected override void afterUpdate() {
        handleAfterUpdate((List<Contract>) Trigger.new);
    }

    @TestVisible
    private static void handleAfterInsert(List<Contract> newContracts) {
        //RES_AccountServices.handleContractAccountSync(newContracts);
    }

    @TestVisible
    private static void handleAfterUpdate(List<Contract> newContracts) {
     RES_ContractServices.syncContract((List<Contract>) Trigger.new, (Map<Id, Contract>) Trigger.oldMap);
    }
    
}
