public with sharing class RES_ContractItemPriceTriggerHandler extends RES_BaseTriggerHandler {

    protected override void afterInsert(){
        RES_ContractItemPriceServices.syncContracts((List<ContractItemPrice>) Trigger.new);
    }

}