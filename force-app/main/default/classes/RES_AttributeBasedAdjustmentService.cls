/**
 * @description Detects AttributeBasedAdjustment changes and publishes Unit_Sync platform events.
 * @author      Roshan Jambhule
 * @date        2025
 */
public with sharing class RES_AttributeBasedAdjustmentService {

    public RES_AttributeBasedAdjustmentService() {}

    /**
     * @description Publishes Unit_Sync events for products whose ABA records have changed.
     *              Null oldMap indicates INSERT context; populated oldMap indicates UPDATE.
     */
    public static void syncUnits(List<AttributeBasedAdjustment> adjustments, Map<Id, AttributeBasedAdjustment> oldMap) {
        Set<Id> productIds = new Set<Id>();

        for (AttributeBasedAdjustment aba : adjustments) {
            if (aba.ProductId == null) continue;

            if (oldMap == null) {
                productIds.add(aba.ProductId);
            } else {
                AttributeBasedAdjustment oldAba = oldMap.get(aba.Id);
                if (oldAba == null || isAdjustmentChanged(aba, oldAba)) {
                    productIds.add(aba.ProductId);
                    if (oldAba != null && oldAba.ProductId != null && oldAba.ProductId != aba.ProductId) {
                        productIds.add(oldAba.ProductId);
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
            System.debug('Exception publishing Unit_Sync events from ABA: ' + e.getMessage());
        }
    }

    /** @description Returns true when any pricing-relevant field differs between old and new records. */
    @TestVisible
    private static Boolean isAdjustmentChanged(AttributeBasedAdjustment newRec, AttributeBasedAdjustment oldRec) {
        return newRec.AdjustmentValue != oldRec.AdjustmentValue
            || newRec.EffectiveFrom  != oldRec.EffectiveFrom
            || newRec.EffectiveTo    != oldRec.EffectiveTo
            || newRec.AdjustmentType != oldRec.AdjustmentType;
    }
}
