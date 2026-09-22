trigger RES_QuoteLineItemTrigger on QuoteLineItem (after insert, after delete, before update) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if(config.RES_Triggers_Off__c == false){
        new RES_QuoteLineItemTriggerHandler().run();
    }
}
