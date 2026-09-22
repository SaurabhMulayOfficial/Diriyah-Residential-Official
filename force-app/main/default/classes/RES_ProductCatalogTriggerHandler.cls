public with sharing class RES_ProductCatalogTriggerHandler extends RES_BaseTriggerHandler {
    public RES_ProductCatalogTriggerHandler() {}
    
    protected override void afterInsert(){
        RES_ProductCatalogServices.syncProductCatalog((List<ProductCatalog>) Trigger.new, null);
    }

    protected override void afterUpdate(){
        RES_ProductCatalogServices.syncProductCatalog((List<ProductCatalog>) Trigger.new, (Map<Id, ProductCatalog>) Trigger.oldMap);
    }
    
}