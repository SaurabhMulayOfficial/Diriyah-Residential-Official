trigger RES_ContractItemPriceTrigger on ContractItemPrice (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if(config.RES_Triggers_Off__c == false){  
        new RES_ContractItemPriceTriggerHandler().run();   
    }
}