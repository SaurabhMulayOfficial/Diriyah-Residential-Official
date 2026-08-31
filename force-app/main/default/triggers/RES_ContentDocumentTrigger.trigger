trigger RES_ContentDocumentTrigger on ContentDocument (after insert, after update, before delete, after delete, after undelete, before insert, before update) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if (config.RES_Triggers_Off__c == false) {  
        new RES_ContentDocumentTriggerHandler().run();   
    }
}