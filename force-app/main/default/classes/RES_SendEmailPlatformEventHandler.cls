public without sharing class RES_SendEmailPlatformEventHandler extends RES_BaseTriggerHandler {
    public RES_SendEmailPlatformEventHandler() {}
    protected override void afterInsert(){
        RES_SendEmailPlatformEventService.processEventsForDuplicationEmails((List<RES_Send_Email__e>) Trigger.new);
    }
}