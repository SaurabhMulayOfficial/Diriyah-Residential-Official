public with sharing class RES_ContractTriggerHandler extends RES_BaseTriggerHandler {
    public RES_ContractTriggerHandler() {}

    protected override void afterInsert(){
        
    }
    
    protected override void afterUpdate(){
        RES_ContractServices.syncContract((List<Contract>) Trigger.new, (Map<Id, Contract>) Trigger.oldMap);
    }
    
}