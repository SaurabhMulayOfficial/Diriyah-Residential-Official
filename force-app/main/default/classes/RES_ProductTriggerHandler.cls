/**
 * @description Trigger handler for Product2; defaults Description from Name and delegates sync to RES_ProductService.
 * @author      Roshan Jambhule
 * @date        2025
 */
public with sharing class RES_ProductTriggerHandler extends RES_BaseTriggerHandler {
    public RES_ProductTriggerHandler() {}

    /** @description Defaults Description to Name when blank and ProductCode is set. */
    protected override void beforeInsert() {
        for (Product2 p : (List<Product2>) Trigger.new) {
            if (String.isBlank(p.Description) && String.isNotBlank(p.ProductCode)) {
                p.Description = p.Name;
            }
        }
    }

    /** @description Publishes Unit_Sync event for newly inserted products. */
    protected override void afterInsert() {
        System.debug('### [RES_ProductTriggerHandler] afterInsert | Records: ' + Trigger.new.size());
        RES_ProductService.syncProducts((List<Product2>) Trigger.new, null);
    }

    /** @description Restores Description from Name when it was cleared and ProductCode is set. */
    protected override void beforeUpdate() {
        for (Product2 p : (List<Product2>) Trigger.new) {
            if (String.isBlank(p.Description) && String.isNotBlank(p.ProductCode)) {
                p.Description = p.Name;
            }
        }
    }

    /** @description Publishes Unit_Sync event for updated products whose sync fields changed. */
    protected override void afterUpdate() {
        System.debug('### [RES_ProductTriggerHandler] afterUpdate | Records: ' + Trigger.new.size());
        RES_ProductService.syncProducts((List<Product2>) Trigger.new, (Map<Id, Product2>) Trigger.oldMap);
    }
}
