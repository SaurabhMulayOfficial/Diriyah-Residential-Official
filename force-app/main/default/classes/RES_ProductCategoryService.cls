/**
 * @description Service layer for Product Category-related business operations.
 *              Provides reusable methods for processing and synchronizing
 *              Product Category records.
 */

public with sharing class RES_ProductCategoryService {
    public RES_ProductCategoryService() {}

    public static void populateFromCatalog(List<ProductCategory> productCategories) {
        Set<Id> catalogIds = new Set<Id>();
        for (ProductCategory pc : productCategories) {
            if (pc.CatalogId != null) {
                catalogIds.add(pc.CatalogId);
            }
        }
        if (catalogIds.isEmpty()) {
            return;
        }

        Map<Id, ProductCatalog> catalogMap = new Map<Id, ProductCatalog>(
            new RES_ProductCatalogDAOLayer().getCatalogByIds(catalogIds)
        );

        for (ProductCategory pc : productCategories) {
            ProductCatalog catalog = catalogMap.get(pc.CatalogId);
            if (catalog == null) {
                continue;
            }
            pc.RES_Valid_From_Date__c = catalog.EffectiveStartDate;
            pc.RES_Valid_To_Date__c = catalog.EffectiveEndDate;
            pc.RES_Profit_Center__c = catalog.RES_Profit_Center__c;
            pc.RES_Company_Code__c = catalog.RES_Company_Code__c;
        }
    }

    public static void syncProductCategories(List<ProductCategory> productCategories, Map<Id, ProductCategory> oldMap){
        List<ProductCategory> categoriesToSync = new List<ProductCategory>();
        RES_SAP_Integration_Config__mdt categoryMDT = new RES_SAPIntegrationConfigDAO().getSAPIntegrationConfigByDeveloperName('Product_Category_Sync');

        if (categoryMDT == null || String.isBlank(categoryMDT.RES_Sync_Fields__c)) {
            throw new RES_IntegrationException(
                'SAP Integration Config is Not available for "Product Category", create and provide at least 1 field for change.'
            );
        }
        
        List<String> syncFieldLst = categoryMDT.RES_Sync_Fields__c.split(',');
        Set<String> syncFields = new Set<String>();

        for (String field : syncFieldLst) {
            if (String.isNotBlank(field)) {
                syncFields.add(field.trim());
            }
        }

        for(ProductCategory pc: productCategories){
            if(oldMap == null || isCategoryChanged(pc, oldMap.get(pc.Id), syncFields)){
                categoriesToSync.add(pc);
            }
        }

        String triggerContext = (oldMap == null? 'I': 'U');

        if (categoriesToSync.isEmpty()) {
            return;
        }

        List<RES_Integration_Request__e> integrationRequestEventList = new List<RES_Integration_Request__e>();        
        for(ProductCategory pc: categoriesToSync){
            RES_Integration_Request__e req = new RES_Integration_Request__e();
            req.RES_RecordIds__c = String.valueOf(pc.Id);
            req.RES_Request_Method__c = 'GET';
            req.RES_Triggering_Context__c = triggerContext;
            req.RES_Service_Name__c = 'ProductCategory_Sync';
            integrationRequestEventList.add(req);
        }

        try{
            if(integrationRequestEventList.size() > 0){
                EventBus.publish(integrationRequestEventList);
            }
        }catch(Exception e){
            System.debug('Exception Firing Integration Request Event ' + e.getMessage());
        }
    }

    private static Boolean isCategoryChanged(ProductCategory newRecord, ProductCategory oldRecord, Set<String> syncFields) {
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