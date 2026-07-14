trigger RES_ProcessAttachmentTrigger on RES_Process_Attachment__e (after insert) {
    new RES_ProcessAttachmentHandler().run();   
}