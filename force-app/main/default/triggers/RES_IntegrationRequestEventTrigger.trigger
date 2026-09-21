trigger RES_IntegrationRequestEventTrigger on RES_Integration_Request__e (after insert) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if(config.RES_Switch_Off_Integrations__c == false){
        new RES_IntegrationRequestEventHandler().run();
    }
}