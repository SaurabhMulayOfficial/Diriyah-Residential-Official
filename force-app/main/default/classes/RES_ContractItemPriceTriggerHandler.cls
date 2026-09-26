public with sharing class RES_ContractItemPriceTriggerHandler extends RES_BaseTriggerHandler {

    @TestVisible private static Boolean isRunning = false;

    @TestVisible
    protected override void afterInsert() {
        if (isRunning) return;
        isRunning = true;
        RES_ContractItemPriceServices.updateFinalPaymentOnContract((List<ContractItemPrice>) Trigger.new);
        handleAfterInsert((List<ContractItemPrice>) Trigger.new);
    }

    @TestVisible
    protected override void afterUpdate() {
        if (isRunning) return;
        isRunning = true;
        handleAfterUpdate((List<ContractItemPrice>) Trigger.new);
    }

    @TestVisible
    protected override void afterDelete() {
        if (isRunning) return;
        isRunning = true;
        handleAfterDelete((List<ContractItemPrice>) Trigger.old);
    }

    @TestVisible
    protected override void afterUndelete() {
        if (isRunning) return;
        isRunning = true;
        handleAfterUndelete((List<ContractItemPrice>) Trigger.new);
    }

    @TestVisible
    private static void handleAfterInsert(List<ContractItemPrice> newCIPs) {
        RES_ContractItemPriceServices.syncContracts(newCIPs);
    }

    @TestVisible
    private static void handleAfterUpdate(List<ContractItemPrice> newCIPs) {
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(newCIPs);
    }

    @TestVisible
    private static void handleAfterDelete(List<ContractItemPrice> oldCIPs) {
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(oldCIPs);
    }

    @TestVisible
    private static void handleAfterUndelete(List<ContractItemPrice> newCIPs) {
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(newCIPs);
    }
}
