/**
 * @description Service class for ContentVersion and ContentDocument business logic.
 * Called from RES_ContentVersionTriggerHandler and RES_ContentDocumentTriggerHandler.
 */
public with sharing class RES_ContentVersionServices {

    // Static variable to prevent recursive execution during automated unchecks
    public static Boolean isExecuting = false;

    // Static map to hold Product Ids associated with ContentDocument Ids before deletion occurs
    private static Map<Id, Set<Id>> docsToProductIdsMapToClear = new Map<Id, Set<Id>>();

    /**
     * @description Processes image uploads and updates Product2 DisplayUrl or unchecks older primary images.
     * @param newVersions List of new ContentVersion records.
     * @param oldMap Map of old ContentVersion records.
     * @param isInsert Boolean flag indicating if transaction is insert.
     */
    public static void handleProductImageUpdates(List<ContentVersion> newVersions, Map<Id, ContentVersion> oldMap, Boolean isInsert) {
        if (newVersions == null || newVersions.isEmpty()) {
            return;
        }

        Set<Id> documentIds = new Set<Id>();
        List<ContentVersion> checkedVersions = new List<ContentVersion>();
        List<ContentVersion> uncheckedVersions = new List<ContentVersion>();

        // 1. Filter records where RES_Want_this_as_product_Image__c has changed
        for (ContentVersion cv : newVersions) {
            Boolean isFieldValueTrue = cv.RES_Want_this_as_product_Image__c;
            Boolean wasChanged = isInsert 
                ? isFieldValueTrue 
                : (isFieldValueTrue != oldMap.get(cv.Id).RES_Want_this_as_product_Image__c);

            if (wasChanged && cv.ContentDocumentId != null) {
                documentIds.add(cv.ContentDocumentId);
                if (isFieldValueTrue) {
                    checkedVersions.add(cv);
                } else {
                    uncheckedVersions.add(cv);
                }
            }
        }

        if (documentIds.isEmpty()) {
            return;
        }

        // 2. Query ContentDocumentLinks bulkified via DAO layer and map to Product2
        Map<Id, Id> docToProductMap = getDocumentToProductMap(documentIds);
        if (docToProductMap.isEmpty()) {
            return;
        }

        // 3. Process checked and unchecked scenarios
        processProductImageUpdates(checkedVersions, uncheckedVersions, docToProductMap);
    }

    /**
     * @description Executed in ContentDocument BEFORE DELETE: Identifies primary image files and maps their Product2 IDs.
     * @param oldDocMap Map of deleted ContentDocument records (Trigger.oldMap).
     */
    public static void prepareProductImageDeletion(Map<Id, ContentDocument> oldDocMap) {
        if (oldDocMap == null || oldDocMap.isEmpty()) {
            return;
        }

        Set<Id> docIds = oldDocMap.keySet();

        // 1. Verify if any of the deleted ContentDocuments are marked as primary image
        List<ContentVersion> primaryVersions = new RES_ContentDocumentDAOLayer().getPrimaryImagesByDocumentIds(docIds);
        if (primaryVersions.isEmpty()) {
            return;
        }

        Set<Id> primaryDocIds = new Set<Id>();
        for (ContentVersion cv : primaryVersions) {
            primaryDocIds.add(cv.ContentDocumentId);
        }

        // 2. Fetch linked Product2 records BEFORE junction links are deleted
        List<ContentDocumentLink> cdlList = new RES_ContentDocumentLinkDAOLayer().getLinksByContentDocumentIds(primaryDocIds);

        for (ContentDocumentLink cdl : cdlList) {
            if (cdl.LinkedEntityId != null && cdl.LinkedEntityId.getSObjectType() == Product2.SObjectType) {
                if (!docsToProductIdsMapToClear.containsKey(cdl.ContentDocumentId)) {
                    docsToProductIdsMapToClear.put(cdl.ContentDocumentId, new Set<Id>());
                }
                docsToProductIdsMapToClear.get(cdl.ContentDocumentId).add(cdl.LinkedEntityId);
            }
        }
    }

    /**
     * @description Executed in ContentDocument AFTER DELETE: Clears DisplayUrl on affected Product2 records.
     */
    public static void executeProductImageDeletion() {
        if (docsToProductIdsMapToClear.isEmpty()) {
            return;
        }

        Map<Id, Product2> productsToUpdate = new Map<Id, Product2>();

        for (Set<Id> prodIdSet : docsToProductIdsMapToClear.values()) {
            for (Id productId : prodIdSet) {
                productsToUpdate.put(productId, new Product2(
                    Id = productId,
                    DisplayUrl = null
                ));
            }
        }

        docsToProductIdsMapToClear.clear();

        if (!productsToUpdate.isEmpty() && Schema.sObjectType.Product2.isUpdateable()) {
            update as user productsToUpdate.values();
        }
    }

    /**
     * @description Queries ContentDocumentLinks via DAO and filters for Product2 associations.
     * @param documentIds Set of ContentDocument IDs.
     * @return Map of ContentDocumentId to Product2 Id.
     */
    private static Map<Id, Id> getDocumentToProductMap(Set<Id> documentIds) {
        Map<Id, Id> docToProductMap = new Map<Id, Id>();
        
        List<ContentDocumentLink> cdlList = new RES_ContentDocumentLinkDAOLayer().getLinksByContentDocumentIds(documentIds);

        for (ContentDocumentLink cdl : cdlList) {
            if (cdl.LinkedEntityId != null && cdl.LinkedEntityId.getSObjectType() == Product2.SObjectType) {
                docToProductMap.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
            }
        }
        return docToProductMap;
    }

    /**
     * @description Updates Product2 records and unchecks previous primary images.
     * @param checkedVersions List of newly checked ContentVersion records.
     * @param uncheckedVersions List of newly unchecked ContentVersion records.
     * @param docToProductMap Map of ContentDocumentId to Product2 Id.
     */
    private static void processProductImageUpdates(
        List<ContentVersion> checkedVersions, 
        List<ContentVersion> uncheckedVersions, 
        Map<Id, Id> docToProductMap
    ) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        Map<Id, Product2> productsToUpdate = new Map<Id, Product2>();
        Set<Id> targetProductIds = new Set<Id>();
        Set<Id> currentCvIds = new Set<Id>();

        // Handle CHECKED scenario
        if (!checkedVersions.isEmpty()) {
            for (ContentVersion cv : checkedVersions) {
                Id productId = docToProductMap.get(cv.ContentDocumentId);
                if (productId != null) {
                    targetProductIds.add(productId);
                    currentCvIds.add(cv.Id);

                    String directDownloadUrl = baseUrl + '/sfc/servlet.shepherd/version/download/' + cv.Id;
                    productsToUpdate.put(productId, new Product2(
                        Id = productId,
                        DisplayUrl = directDownloadUrl
                    ));
                }
            }

            // Uncheck previous primary images on the same Product(s)
            if (!targetProductIds.isEmpty()) {
                uncheckPreviousPrimaryImages(targetProductIds, currentCvIds);
            }
        }

        // Handle UNCHECKED scenario: Erase DisplayUrl if no new image replaces it in current payload
        if (!uncheckedVersions.isEmpty()) {
            for (ContentVersion cv : uncheckedVersions) {
                Id productId = docToProductMap.get(cv.ContentDocumentId);
                if (productId != null && !productsToUpdate.containsKey(productId)) {
                    productsToUpdate.put(productId, new Product2(
                        Id = productId,
                        DisplayUrl = null
                    ));
                }
            }
        }

        // Perform DML Update
        if (!productsToUpdate.isEmpty() && Schema.sObjectType.Product2.isUpdateable()) {
            update as user productsToUpdate.values();
        }
    }

    /**
     * @description Queries and unchecks previous primary image ContentVersions on target products using DAO layers.
     * @param targetProductIds Set of Product2 IDs.
     * @param currentCvIds Set of current transaction ContentVersion IDs to exclude.
     */
    private static void uncheckPreviousPrimaryImages(Set<Id> targetProductIds, Set<Id> currentCvIds) {
        List<ContentDocumentLink> productCdls = new RES_ContentDocumentLinkDAOLayer().getLinksByLinkedEntityIds(targetProductIds);

        Set<Id> relatedDocIds = new Set<Id>();
        for (ContentDocumentLink cdl : productCdls) {
            relatedDocIds.add(cdl.ContentDocumentId);
        }

        if (relatedDocIds.isEmpty()) {
            return;
        }

        List<ContentVersion> previousPrimaryImages = new RES_ContentVersionDAOLayer().getPreviousPrimaryImages(relatedDocIds, currentCvIds);

        if (!previousPrimaryImages.isEmpty()) {
            for (ContentVersion oldCv : previousPrimaryImages) {
                oldCv.RES_Want_this_as_product_Image__c = false;
            }

            // Set recursion flag to prevent infinite re-triggering
            isExecuting = true;
            if (Schema.sObjectType.ContentVersion.isUpdateable()) {
                update as user previousPrimaryImages;
            }
            isExecuting = false;
        }
    }
}