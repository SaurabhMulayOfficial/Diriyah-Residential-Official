public with sharing class RES_IntegrationRequestEventHandler extends RES_BaseTriggerHandler {
    public RES_IntegrationRequestEventHandler() {}

    protected override void afterInsert(){
        RES_IntegrationRequestEventService.handleIntegrations((List<RES_Integration_Request__e>)Trigger.new);
    }
}