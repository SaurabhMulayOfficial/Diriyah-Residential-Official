public with sharing class RES_ContractTriggerHandler extends RES_BaseTriggerHandler {
    public RES_ContractTriggerHandler() {}

    protected override void beforeInsert() {
        RES_ContractServices.populateCustomerSignedBy((List<Contract>) Trigger.new);
    }

  protected override void afterInsert() {
        handleAfterInsert((List<Contract>) Trigger.new);
    }
    
    protected override void beforeUpdate() {
        handleBeforeUpdate((List<Contract>) Trigger.new, (Map<Id, Contract>) Trigger.oldMap);
    }

    protected override void afterUpdate() {
        handleAfterUpdate((List<Contract>) Trigger.new, (Map<Id, Contract>) Trigger.oldMap);
    }

    @TestVisible
    private static void handleAfterInsert(List<Contract> newContracts) {
        RES_AccountServices.handleContractAccountSync(newContracts);
    }

    @TestVisible
    private static void handleBeforeUpdate(List<Contract> newContracts, Map<Id, Contract> oldMap) {
        setFeeTransferredOnFirstAmountReceived(newContracts, oldMap);
    }

    // Mark fee as transferred when Last Amount Received is populated for the first time
    @TestVisible
    private static void setFeeTransferredOnFirstAmountReceived(List<Contract> newContracts, Map<Id, Contract> oldMap) {
        for (Contract c : newContracts) {
            Contract old = oldMap.get(c.Id);
            if (old != null && old.RES_Last_Amount_Received__c == null
                    && c.RES_Last_Amount_Received__c != null && !c.RES_Fee_Transferred__c) {
                c.RES_Fee_Transferred__c = true;
            }
        }
    }

    @TestVisible
    private static void handleAfterUpdate(List<Contract> newContracts, Map<Id, Contract> oldMap) {
        RES_ContractServices.syncContract(newContracts, oldMap);
    }
    
}
