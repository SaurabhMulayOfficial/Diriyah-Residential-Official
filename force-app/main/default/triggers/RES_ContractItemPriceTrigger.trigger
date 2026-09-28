trigger RES_ContractItemPriceTrigger on ContractItemPrice (after insert, after update, after delete, after undelete) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if (config.RES_Triggers_Off__c == false) {
        new RES_ContractItemPriceTriggerHandler().run();
    }
}
