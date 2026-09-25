public with sharing class RES_ContractItemPriceTriggerHandler extends RES_BaseTriggerHandler {

    private static Boolean isRunning = false;

    protected override void afterInsert() {
        if (isRunning) return;
        isRunning = true;
        RES_ContractItemPriceService.updateFinalPaymentOnContract((List<ContractItemPrice>) Trigger.new);
    }

    protected override void afterUpdate() {
        if (isRunning) return;
        isRunning = true;
        RES_ContractItemPriceService.updateFinalPaymentOnContract((List<ContractItemPrice>) Trigger.new);
    }

    protected override void afterDelete() {
        if (isRunning) return;
        isRunning = true;
        RES_ContractItemPriceService.updateFinalPaymentOnContract((List<ContractItemPrice>) Trigger.old);
    }

    protected override void afterUndelete() {
        if (isRunning) return;
        isRunning = true;
        RES_ContractItemPriceService.updateFinalPaymentOnContract((List<ContractItemPrice>) Trigger.new);
    }
}
