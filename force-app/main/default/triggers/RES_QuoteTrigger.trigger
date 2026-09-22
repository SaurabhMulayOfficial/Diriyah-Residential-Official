trigger RES_QuoteTrigger on Quote (before update) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if(config.RES_Triggers_Off__c == false){
        new RES_QuoteTriggerHandler().run();
    }
}
