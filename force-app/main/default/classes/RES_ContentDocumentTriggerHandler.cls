/*
 * @description ContentDocument Trigger Handler class. Calls service methods from RES_ContentVersionServices.
 */
public with sharing class RES_ContentDocumentTriggerHandler extends RES_BaseTriggerHandler {

    protected override void beforeDelete() {
        if (!RES_ContentVersionServices.isExecuting) {
            RES_ContentVersionServices.prepareProductImageDeletion(
                (Map<Id, ContentDocument>) Trigger.oldMap
            );
        }
    }

    protected override void afterDelete() {
        if (!RES_ContentVersionServices.isExecuting) {
            RES_ContentVersionServices.executeProductImageDeletion();
        }
    }
}