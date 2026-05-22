/*
    * Use Utility/Service classes to implement the logic. And call those methods from Trigger Handler.
*/

trigger LeadTrigger on Lead (after insert, after update, after delete, after undelete, before insert, before update, before delete) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if(config.RES_Triggers_Off__c == false){  
        new RES_LeadTriggerHandler().run();   
    }
}