trigger RES_AssignmentRuleTrigger on RES_Assignment_Rule__c (after insert, after update) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if(config.RES_Triggers_Off__c == false){
        new RES_AssignmentRuleTriggerHandler().run();
    }
}