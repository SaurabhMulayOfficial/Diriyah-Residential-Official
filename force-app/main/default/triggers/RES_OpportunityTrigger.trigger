trigger RES_OpportunityTrigger on Opportunity (before insert, before update, after insert, after update, after delete){
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if(config.RES_Triggers_Off__c == false){  
        new RES_OpportunityTriggerHandler().run();   
    }
}