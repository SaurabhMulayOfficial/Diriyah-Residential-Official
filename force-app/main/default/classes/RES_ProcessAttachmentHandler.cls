/**
 * @description  Handler Class for RES_Process_Attachment__e Platform Event.
 * @author       Saurabh Mulay
 * @date         14-Jul-2026
 * @version      1.0
 */

public with sharing class RES_ProcessAttachmentHandler extends RES_BaseTriggerHandler {
    protected override void afterInsert(){
        RES_ProcessAttachmentService.processAttachments((List<RES_Process_Attachment__e>) trigger.new);
    }
}