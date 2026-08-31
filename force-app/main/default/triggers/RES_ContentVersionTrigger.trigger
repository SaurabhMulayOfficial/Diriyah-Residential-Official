/**
 * @description Trigger on ContentVersion object to manage Product catalog thumbnail images.
 */
trigger RES_ContentVersionTrigger on ContentVersion (after insert, after update, after delete, after undelete, before insert, before update, before delete) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if (config.RES_Triggers_Off__c == false) {  
        new RES_ContentVersionTriggerHandler().run();   
    }
}