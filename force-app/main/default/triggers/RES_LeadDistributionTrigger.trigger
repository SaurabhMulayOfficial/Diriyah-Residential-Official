trigger RES_LeadDistributionTrigger on RES_Lead_Distribution__e (after insert) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if(config.RES_Triggers_Off__c == false){  
        new RES_LeadDistributionHandler().run();
    }   
}