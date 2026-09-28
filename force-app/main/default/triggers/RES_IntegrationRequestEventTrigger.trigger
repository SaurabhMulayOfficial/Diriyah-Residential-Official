trigger RES_IntegrationRequestEventTrigger on RES_Integration_Request__e (after insert) {
    System.debug('### [RES_IntegrationRequestEventTrigger] Fired | Events: ' + Trigger.new.size());
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    System.debug('### [RES_IntegrationRequestEventTrigger] Switch_Off_Integrations: ' + config.RES_Switch_Off_Integrations__c);
    if(config.RES_Switch_Off_Integrations__c == false){
        System.debug('### [RES_IntegrationRequestEventTrigger] Calling handler');
        new RES_IntegrationRequestEventHandler().run();
    }
}