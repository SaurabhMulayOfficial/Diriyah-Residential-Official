/**
 * @description Detects AttributeBasedAdjustment changes and publishes Unit_Sync platform events.
 * @author      Roshan Jambhule
 * @date        2025
 */
public with sharing class RES_AttributeBasedAdjustmentService {

    public RES_AttributeBasedAdjustmentService() {}

    /**
     * @description Publishes Unit_Sync events for products whose ABA records have changed.
     *              Sync fields are driven by the ABA_Sync custom metadata record.
     *              Null oldMap indicates INSERT context; populated oldMap indicates UPDATE.
     */
    public static void syncUnits(List<AttributeBasedAdjustment> adjustments, Map<Id, AttributeBasedAdjustment> oldMap) {
        RES_SAP_Integration_Config__mdt abaMDT = new RES_SAPIntegrationConfigDAO().getSAPIntegrationConfigByDeveloperName('ABA_Sync');
        System.debug('### [RES_AttributeBasedAdjustmentService] ABA_Sync MDT found: ' + (abaMDT != null));

        if (abaMDT == null || String.isBlank(abaMDT.RES_Sync_Fields__c)) {
            System.debug('### [RES_AttributeBasedAdjustmentService] ERROR: ABA_Sync MDT missing or no sync fields');
            throw new RES_IntegrationException(
                'SAP Integration Config is Not available for "ABA Sync", create and provide at least 1 field for change.'
            );
        }

        Set<String> syncFields = new Set<String>();
        for (String field : abaMDT.RES_Sync_Fields__c.split(',')) {
            if (String.isNotBlank(field)) {
                syncFields.add(field.trim());
            }
        }

        Set<Id> productIds = new Set<Id>();

        for (AttributeBasedAdjustment aba : adjustments) {
            if (aba.ProductId == null) continue;

            if (oldMap == null) {
                productIds.add(aba.ProductId);
            } else {
                AttributeBasedAdjustment oldAba = oldMap.get(aba.Id);
                if (oldAba == null || isAdjustmentChanged(aba, oldAba, syncFields)) {
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

    /** @description Returns true when any configured sync field value differs between old and new records. */
    @TestVisible
    private static Boolean isAdjustmentChanged(AttributeBasedAdjustment newRec, AttributeBasedAdjustment oldRec, Set<String> syncFields) {
        for (String fieldName : syncFields) {
            try {
                Object newValue = newRec.get(fieldName);
                Object oldValue = oldRec.get(fieldName);
                if (String.valueOf(newValue) != String.valueOf(oldValue)) {
                    return true;
                }
            } catch (SObjectException e) {
                System.debug('Invalid sync field "' + fieldName + '" for AttributeBasedAdjustment, skipping: ' + e.getMessage());
            }
        }
        return false;
    }
}
