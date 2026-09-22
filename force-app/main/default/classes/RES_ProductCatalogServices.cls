/**
 * @description Service layer for Product Catalog-related business operations.
 *              Provides reusable methods for processing and synchronizing
 *              Product Catalog records.
 *
 * @author Saurabh Mulay
 */

public with sharing class RES_ProductCatalogServices {
    public RES_ProductCatalogServices() {}

    public static void syncProductCatalog(List<ProductCatalog> catalogs, Map<Id, ProductCatalog> oldMap) {
        List<ProductCatalog> catalogsToSync = new List<ProductCatalog>();
        RES_SAP_Integration_Config__mdt catalogMDT = new RES_SAPIntegrationConfigDAO().getSAPIntegrationConfigByDeveloperName('Product_Catalog_Sync');

        if (catalogMDT == null || String.isBlank(catalogMDT.RES_Sync_Fields__c)) {
            throw new RES_IntegrationException(
                'SAP Integration Config is Not available for "Product Catalog", create and provide at least 1 field for change.'
            );
        }

        List<String> syncFieldLst = catalogMDT.RES_Sync_Fields__c.split(',');
        Set<String> syncFields = new Set<String>();

        for (String field : syncFieldLst) {
            if (String.isNotBlank(field)) {
                syncFields.add(field.trim());
            }
        }

        for (ProductCatalog pc : catalogs) {
            if (oldMap == null || isCatalogChanged(pc, oldMap.get(pc.Id), syncFields)) {
                catalogsToSync.add(pc);
            }
        }

        if (catalogsToSync.isEmpty()) {
            return;
        }

        String triggerContext = (oldMap == null ? 'I' : 'U');

        List<RES_Integration_Request__e> integrationRequestEventList = new List<RES_Integration_Request__e>();
        for (ProductCatalog pc : catalogsToSync) {
            RES_Integration_Request__e req = new RES_Integration_Request__e();
            req.RES_RecordIds__c = String.valueOf(pc.Id);
            req.RES_Request_Method__c = 'GET';
            req.RES_Triggering_Context__c = triggerContext;
            req.RES_Service_Name__c = 'ProductCatalog_Sync';
            integrationRequestEventList.add(req);
        }

        try {
            if (!integrationRequestEventList.isEmpty()) {
                EventBus.publish(integrationRequestEventList);
            }
        } catch (Exception e) {
            System.debug('Exception Firing Integration Request Event ' + e.getMessage());
        }
    }

    private static Boolean isCatalogChanged(ProductCatalog newRecord, ProductCatalog oldRecord, Set<String> syncFields) {
        if (oldRecord == null) {
            return true;
        }

        for (String fieldName : syncFields) {
            Object newValue = newRecord.get(fieldName);
            Object oldValue = oldRecord.get(fieldName);

            if (String.valueOf(newValue) != String.valueOf(oldValue)) {
                return true;
            }
        }
        return false;
    }
}
