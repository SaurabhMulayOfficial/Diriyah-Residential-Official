trigger RES_ProductTrigger on Product2 (before insert, before update, after insert, after update) {
    System.debug('### [RES_ProductTrigger] Fired | Event: ' + Trigger.operationType + ' | Records: ' + Trigger.size);
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    System.debug('### [RES_ProductTrigger] Triggers_Off: ' + config.RES_Triggers_Off__c);
    if (config.RES_Triggers_Off__c == false) {
        new RES_ProductTriggerHandler().run();
    }
}
