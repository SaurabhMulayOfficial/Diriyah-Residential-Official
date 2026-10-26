/**
 * @description Service layer for Product2-related business operations.
 *              Provides reusable methods for processing and synchronizing
 *              Product2 records.
 */

public with sharing class RES_ProductService {
    public RES_ProductService() {}

    public static void syncProducts(List<Product2> products, Map<Id, Product2> oldMap) {
        System.debug('### [RES_ProductService] syncProducts | Products: ' + products.size() + ' | isInsert: ' + (oldMap == null));
        List<Product2> productsToSync = new List<Product2>();
        RES_SAP_Integration_Config__mdt productMDT = new RES_SAPIntegrationConfigDAO().getSAPIntegrationConfigByDeveloperName('Unit_Sync');
        System.debug('### [RES_ProductService] Unit_Sync MDT found: ' + (productMDT != null));

        if (productMDT == null || String.isBlank(productMDT.RES_Sync_Fields__c)) {
            System.debug('### [RES_ProductService] ERROR: Unit_Sync MDT missing or no sync fields');
            throw new RES_IntegrationException(
                'SAP Integration Config is Not available for "Unit Sync", create and provide at least 1 field for change.'
            );
        }

        List<String> syncFieldLst = productMDT.RES_Sync_Fields__c.split(',');
        Set<String> syncFields = new Set<String>();

        for (String field : syncFieldLst) {
            if (String.isNotBlank(field)) {
                syncFields.add(field.trim());
            }
        }

        for (Product2 p : products) {
            if (oldMap == null || isProductChanged(p, oldMap.get(p.Id), syncFields)) {
                productsToSync.add(p);
            }
        }

        String triggerContext = (oldMap == null ? 'I' : 'U');

        System.debug('### [RES_ProductService] productsToSync count: ' + productsToSync.size());
        if (productsToSync.isEmpty()) {
            System.debug('### [RES_ProductService] No changed products — skipping event publish');
            return;
        }

        List<RES_Integration_Request__e> integrationRequestEventList = new List<RES_Integration_Request__e>();
        for (Product2 p : productsToSync) {
            RES_Integration_Request__e req = new RES_Integration_Request__e();
            req.RES_RecordIds__c = String.valueOf(p.Id);
            req.RES_Request_Method__c = 'GET';
            req.RES_Triggering_Context__c = triggerContext;
            req.RES_Service_Name__c = 'Unit_Sync';
            integrationRequestEventList.add(req);
        }

        try {
            if (integrationRequestEventList.size() > 0) {
                System.debug('### [RES_ProductService] Publishing ' + integrationRequestEventList.size() + ' RES_Integration_Request__e events');
                EventBus.publish(integrationRequestEventList);
                System.debug('### [RES_ProductService] Events published successfully');
            }
        } catch (Exception e) {
            System.debug('### [RES_ProductService] Exception Firing Integration Request Event: ' + e.getMessage());
        }
    }

    @TestVisible
    private static Boolean isProductChanged(Product2 newRecord, Product2 oldRecord, Set<String> syncFields) {
        if (oldRecord == null) {
            return true;
        }

        for (String fieldName : syncFields) {
            try {
                Object newValue = newRecord.get(fieldName);
                Object oldValue = oldRecord.get(fieldName);
                if (String.valueOf(newValue) != String.valueOf(oldValue)) {
                    return true;
                }
            } catch (SObjectException e) {
                System.debug('Invalid sync field "' + fieldName + '" for Product2, skipping: ' + e.getMessage());
            }
        }
        return false;
    }

    /** Test-only override of the configured groups (Chatter group name => share type); custom metadata cannot be inserted in tests. */
    @TestVisible
    private static Map<String, String> shareGroupOverride;

    /**
     * @description Returns the active Chatter groups document images are shared with, as group name => share type,
     *              read from RES_Document_Image_Share_Group__mdt. Add a record there to share with a new group.
     */
    @TestVisible
    private static Map<String, String> getDocumentImageShareGroups() {
        if (shareGroupOverride != null) {
            return shareGroupOverride;
        }
        Map<String, String> shareTypeByGroup = new Map<String, String>();
        for (RES_Document_Image_Share_Group__mdt cfg : RES_Document_Image_Share_Group__mdt.getAll().values()) {
            if (cfg.RES_Is_Active__c && String.isNotBlank(cfg.RES_Group_Name__c)) {
                shareTypeByGroup.put(cfg.RES_Group_Name__c.trim(), cfg.RES_Share_Type__c);
            }
        }
        return shareTypeByGroup;
    }

    /**
     * @description When RES_SPA_Document_Image_Name__c is set or changed, shares every file on the product whose
     *              title matches the name with the Chatter groups configured in RES_Document_Image_Share_Group__mdt,
     *              so the image renders in generated documents. Existing links (uploader, owner) are untouched.
     */
    public static void shareDocumentImages(List<Product2> products, Map<Id, Product2> oldMap) {
        Map<Id, String> nameByProduct = new Map<Id, String>();
        for (Product2 p : products) {
            if (String.isBlank(p.RES_SPA_Document_Image_Name__c)) {
                continue;
            }
            if (oldMap == null || p.RES_SPA_Document_Image_Name__c != oldMap.get(p.Id).RES_SPA_Document_Image_Name__c) {
                nameByProduct.put(p.Id, p.RES_SPA_Document_Image_Name__c.trim().toLowerCase());
            }
        }
        if (nameByProduct.isEmpty()) {
            return;
        }

        Set<Id> matchedDocIds = new Set<Id>();
        for (ContentDocumentLink cdl : new RES_ContentDocumentLinkDAOLayer().getLinksWithTitleByLinkedEntityIds(nameByProduct.keySet())) {
            String title = cdl.ContentDocument.Title;
            if (title != null && title.trim().toLowerCase() == nameByProduct.get(cdl.LinkedEntityId)) {
                matchedDocIds.add(cdl.ContentDocumentId);
            }
        }
        if (matchedDocIds.isEmpty()) {
            return;
        }

        Map<String, String> shareTypeByGroupName = getDocumentImageShareGroups();
        Map<Id, String> shareTypeByGroupId = new Map<Id, String>();
        for (CollaborationGroup g : new RES_CollaborationGroupDAOLayer().getGroupsByNames(shareTypeByGroupName.keySet())) {
            String shareType = shareTypeByGroupName.get(g.Name);
            shareTypeByGroupId.put(g.Id, (shareType == 'C' || shareType == 'I') ? shareType : 'V');
        }
        if (shareTypeByGroupId.isEmpty()) {
            System.debug(LoggingLevel.WARN, '### [RES_ProductService] Document image share Chatter groups not configured or not found');
            return;
        }

        Set<String> existing = new Set<String>();
        for (ContentDocumentLink cdl : new RES_ContentDocumentLinkDAOLayer().getContentDocumentLinkByContentDocumentId(matchedDocIds)) {
            existing.add(cdl.ContentDocumentId + '-' + cdl.LinkedEntityId);
        }

        List<ContentDocumentLink> toInsert = new List<ContentDocumentLink>();
        for (Id docId : matchedDocIds) {
            for (Id groupId : shareTypeByGroupId.keySet()) {
                if (!existing.contains(docId + '-' + groupId)) {
                    toInsert.add(new ContentDocumentLink(
                        ContentDocumentId = docId,
                        LinkedEntityId = groupId,
                        ShareType = shareTypeByGroupId.get(groupId),
                        Visibility = 'AllUsers'
                    ));
                }
            }
        }
        if (toInsert.isEmpty()) {
            return;
        }
        for (Database.SaveResult sr : Database.insert(toInsert, false)) {
            if (!sr.isSuccess()) {
                System.debug(LoggingLevel.ERROR, '### [RES_ProductService] Document image share failed: ' + sr.getErrors()[0].getMessage());
            }
        }
    }
}