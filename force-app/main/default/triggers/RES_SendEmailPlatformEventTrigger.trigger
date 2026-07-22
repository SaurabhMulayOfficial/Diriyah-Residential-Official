trigger RES_SendEmailPlatformEventTrigger on RES_Send_Email__e (after insert) {
    new RES_SendEmailPlatformEventHandler().run();
}