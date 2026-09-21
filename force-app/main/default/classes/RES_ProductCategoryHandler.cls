public with sharing class RES_ProductCategoryHandler extends RES_BaseTriggerHandler {
    public RES_ProductCategoryHandler() {}

    protected override void beforeInsert() {
    }

    protected override void afterInsert(){
        RES_ProductCategoryService.syncProductCategories((List<ProductCategory>) Trigger.new, null);
    }

    protected override void beforeUpdate() {
    }

    protected override void afterUpdate() {
        RES_ProductCategoryService.syncProductCategories((List<ProductCategory>) Trigger.new, (Map<Id, ProductCategory>) Trigger.oldMap);
    }
}