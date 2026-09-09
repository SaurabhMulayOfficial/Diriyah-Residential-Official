trigger RES_QuoteLineItemTrigger on QuoteLineItem (before update) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if(config.RES_Triggers_Off__c == false){
        RES_QuoteLineItemLockHandler.enforceLock(Trigger.new, Trigger.oldMap);
    }
}
