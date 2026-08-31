/**
 * @description ContentVersion Trigger Handler class. Calls service methods from RES_ContentVersionServices.
 */
public with sharing class RES_ContentVersionTriggerHandler extends RES_BaseTriggerHandler {

    protected override void afterInsert() {
        if (!RES_ContentVersionServices.isExecuting) {
            RES_ContentVersionServices.handleProductImageUpdates(
                (List<ContentVersion>) Trigger.new, 
                null, 
                true
            );
        }
    }

    protected override void afterUpdate() {
        if (!RES_ContentVersionServices.isExecuting) {
            RES_ContentVersionServices.handleProductImageUpdates(
                (List<ContentVersion>) Trigger.new, 
                (Map<Id, ContentVersion>) Trigger.oldMap, 
                false
            );
        }
    }
}