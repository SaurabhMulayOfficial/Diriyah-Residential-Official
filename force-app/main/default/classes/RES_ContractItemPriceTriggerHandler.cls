public with sharing class RES_ContractItemPriceTriggerHandler extends RES_BaseTriggerHandler {

    protected override void afterInsert(){
        handleAfterInsert((List<ContractItemPrice>) Trigger.new);
    }

    @TestVisible
    private static void handleAfterInsert(List<ContractItemPrice> newCIPs) {
        RES_ContractItemPriceServices.syncContracts(newCIPs);
    }

}