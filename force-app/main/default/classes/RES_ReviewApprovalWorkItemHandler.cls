/**
 * ==============================================================================
 * Class Name    : RES_ReviewApprovalWorkItemHandler
 * Description   : Trigger handler for Review Approval Work Item platform events.
 *                 Delegates after-insert event processing to the service layer.
 * Author        : Saurabh Mulay
 * Company       : Globant Inc
 * ==============================================================================
 */

public with sharing class RES_ReviewApprovalWorkItemHandler extends RES_BaseTriggerHandler {
    public RES_ReviewApprovalWorkItemHandler() {}
    
    protected override void afterInsert() {
        RES_ReviewApprovalWorkItemService.filter((List<RES_Review_Approval_Work_Item__e>) Trigger.new);
    }
}