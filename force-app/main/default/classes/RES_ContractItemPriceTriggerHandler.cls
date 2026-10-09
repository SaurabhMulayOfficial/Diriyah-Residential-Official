public with sharing class RES_ContractItemPriceTriggerHandler extends RES_BaseTriggerHandler {

    @TestVisible private static Boolean isRunning = false;

    protected override void afterInsert() {
        handleAfterInsert((List<ContractItemPrice>) Trigger.new);
    }

    protected override void afterUpdate() {
        handleAfterUpdate((List<ContractItemPrice>) Trigger.new);
    }

    protected override void afterDelete() {
        handleAfterDelete((List<ContractItemPrice>) Trigger.old);
    }

    protected override void afterUndelete() {
        handleAfterUndelete((List<ContractItemPrice>) Trigger.new);
    }

    @TestVisible
    private static void handleAfterInsert(List<ContractItemPrice> newCIPs) {
        // No isRunning guard: the services only write to Contract, and CIPs are inserted in several
        // DMLs per transaction (CreateContract action, then the installment flow).
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(newCIPs);
        RES_ContractItemPriceServices.syncContracts(newCIPs);
    }

    @TestVisible
    private static void handleAfterUpdate(List<ContractItemPrice> newCIPs) {
        if (isRunning) return;
        isRunning = true;
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(newCIPs);
    }

    @TestVisible
    private static void handleAfterDelete(List<ContractItemPrice> oldCIPs) {
        if (isRunning) return;
        isRunning = true;
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(oldCIPs);
    }

    @TestVisible
    private static void handleAfterUndelete(List<ContractItemPrice> newCIPs) {
        if (isRunning) return;
        isRunning = true;
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(newCIPs);
    }
}