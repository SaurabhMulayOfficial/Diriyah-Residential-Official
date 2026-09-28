/**
 * @description Detects ProductAttributeDefinition changes and publishes Unit_Sync platform events.
 * @author      Roshan Jambhule
 * @date        2025
 */
public with sharing class RES_ProductAttributeDefinitionService {

    public RES_ProductAttributeDefinitionService() {}

    /**
     * @description Publishes Unit_Sync events for products whose PAD records have changed.
     *              Null oldMap indicates INSERT context; populated oldMap indicates UPDATE.
     */
    public static void syncUnits(List<ProductAttributeDefinition> definitions, Map<Id, ProductAttributeDefinition> oldMap) {
        Set<Id> productIds = new Set<Id>();

        for (ProductAttributeDefinition pad : definitions) {
            if (pad.Product2Id == null) continue;

            if (oldMap == null) {
                productIds.add(pad.Product2Id);
            } else {
                ProductAttributeDefinition oldPad = oldMap.get(pad.Id);
                if (oldPad == null || isDefinitionChanged(pad, oldPad)) {
                    productIds.add(pad.Product2Id);
                    if (oldPad != null && oldPad.Product2Id != null && oldPad.Product2Id != pad.Product2Id) {
                        productIds.add(oldPad.Product2Id);
                    }
                }
            }
        }

        if (productIds.isEmpty()) return;

        String triggerContext = oldMap == null ? 'I' : 'U';
        List<RES_Integration_Request__e> events = new List<RES_Integration_Request__e>();
        for (Id productId : productIds) {
            RES_Integration_Request__e evt = new RES_Integration_Request__e();
            evt.RES_RecordIds__c          = String.valueOf(productId);
            evt.RES_Request_Method__c     = 'GET';
            evt.RES_Service_Name__c       = 'Unit_Sync';
            evt.RES_Triggering_Context__c = triggerContext;
            events.add(evt);
        }

        try {
            EventBus.publish(events);
        } catch (Exception e) {
            System.debug('Exception publishing Unit_Sync events from PAD: ' + e.getMessage());
        }
    }

    /** @description Returns true when any pricing-relevant field differs between old and new records. */
    @TestVisible
    private static Boolean isDefinitionChanged(ProductAttributeDefinition newRec, ProductAttributeDefinition oldRec) {
        return newRec.DefaultValue      != oldRec.DefaultValue
            || newRec.RES_Valid_From__c != oldRec.RES_Valid_From__c
            || newRec.RES_Valid_To__c   != oldRec.RES_Valid_To__c
            || newRec.Status            != oldRec.Status;
    }
}
