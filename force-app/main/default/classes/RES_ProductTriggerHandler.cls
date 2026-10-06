/**
 * @description Trigger handler for Product2; defaults Description from Name and delegates sync to RES_ProductService.
 * @author      Roshan Jambhule
 * @date        2025
 */
public with sharing class RES_ProductTriggerHandler extends RES_BaseTriggerHandler {

    private static final Date DISCONTINUED_DEFAULT = Date.newInstance(2099, 12, 31);

    public RES_ProductTriggerHandler() {}

    /** @description Defaults Description to Name when blank; defaults AvailabilityDate to today and DiscontinuedDate to 2099-12-31 when blank.
     *              Always clears RES_Product_External_ID__c — SAP owns this field and must assign it on INSERT. */
    protected override void beforeInsert() {
        Date today = Date.today();
        for (Product2 p : (List<Product2>) Trigger.new) {
            if (String.isBlank(p.Description) && String.isNotBlank(p.ProductCode)) {
                p.Description = p.Name;
            }
            if (p.AvailabilityDate == null) {
                p.AvailabilityDate = today;
            }
            if (p.DiscontinuedDate == null) {
                p.DiscontinuedDate = DISCONTINUED_DEFAULT;
            }
            // SAP assigns ExternalId on INSERT response — clear any value set by upload sheets or data loads
            p.RES_Product_External_ID__c = null;
        }
    }

    /** @description Publishes Unit_Sync event for newly inserted products. */
    protected override void afterInsert() {
        System.debug('### [RES_ProductTriggerHandler] afterInsert | Records: ' + Trigger.new.size());
        RES_ProductService.syncProducts((List<Product2>) Trigger.new, null);
    }

    /** @description Restores Description from Name when cleared; re-defaults AvailabilityDate/DiscontinuedDate if explicitly cleared; blocks a Residential Sales unit from being set Active or Available without its Service Charge Rate attribute override. */
    protected override void beforeUpdate() {
        Date today = Date.today();
        for (Product2 p : (List<Product2>) Trigger.new) {
            if (String.isBlank(p.Description) && String.isNotBlank(p.ProductCode)) {
                p.Description = p.Name;
            }
            if (p.AvailabilityDate == null) {
                p.AvailabilityDate = today;
            }
            if (p.DiscontinuedDate == null) {
                p.DiscontinuedDate = DISCONTINUED_DEFAULT;
            }
        }
        RES_ProductSCRateValidation.validate((List<Product2>) Trigger.new, (Map<Id, Product2>) Trigger.oldMap);
    }

    /** @description Publishes Unit_Sync event for updated products whose sync fields changed. */
    protected override void afterUpdate() {
        System.debug('### [RES_ProductTriggerHandler] afterUpdate | Records: ' + Trigger.new.size());
        RES_ProductService.syncProducts((List<Product2>) Trigger.new, (Map<Id, Product2>) Trigger.oldMap);
        RES_PaymentPlanServices.syncPaymentPlans((List<Product2>) Trigger.new, (Map<Id, Product2>) Trigger.oldMap);
    }
}