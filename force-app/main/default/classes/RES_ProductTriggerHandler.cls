/**
 * @description Trigger handler for Product2; defaults Description from Name and delegates sync to RES_ProductService.
 * @author      Roshan Jambhule
 * @date        2025
 */
public with sharing class RES_ProductTriggerHandler extends RES_BaseTriggerHandler {

    public RES_ProductTriggerHandler() {}

    /** @description Inherits dates/profit center from the parent, then defaults any blank validity dates. */
    protected override void beforeInsert() {
        RES_ProductParentInheritanceService.applyParentValues((List<Product2>) Trigger.new, null);
        RES_ProductService.applyDateDefaults((List<Product2>) Trigger.new);
    }

    /** @description Publishes Unit_Sync event for newly inserted products. */
    protected override void afterInsert() {
        System.debug('### [RES_ProductTriggerHandler] afterInsert | Records: ' + Trigger.new.size());
        RES_ProductService.syncProducts((List<Product2>) Trigger.new, null);
        RES_PaymentPlanServices.syncPaymentPlans((List<Product2>) Trigger.new, null);
    }

    /** @description Re-defaults AvailabilityDate/DiscontinuedDate if explicitly cleared; blocks a Residential Sales unit from being set Active or Available without its Service Charge Rate attribute override; stamps the default plan price on activation. */
    protected override void beforeUpdate() {
        RES_ProductParentInheritanceService.applyParentValues((List<Product2>) Trigger.new, (Map<Id, Product2>) Trigger.oldMap);
        RES_ProductService.applyDateDefaults((List<Product2>) Trigger.new);
        RES_ProductSCRateValidation.validate((List<Product2>) Trigger.new, (Map<Id, Product2>) Trigger.oldMap);
        RES_UnitDraftCancellationService.releaseReservations((List<Product2>) Trigger.new, (Map<Id, Product2>) Trigger.oldMap);
        RES_DefaultPlanPriceService.applyOnActivation((List<Product2>) Trigger.new, (Map<Id, Product2>) Trigger.oldMap);
    }

    /** @description Publishes Unit_Sync event for updated products whose sync fields changed. */
    protected override void afterUpdate() {
        RES_ProductService.syncProducts((List<Product2>) Trigger.new, (Map<Id, Product2>) Trigger.oldMap);
        RES_PaymentPlanServices.syncPaymentPlans((List<Product2>) Trigger.new, (Map<Id, Product2>) Trigger.oldMap);
        RES_PaymentPlanServices.removeDeactivatedPlansFromUnits((List<Product2>) Trigger.new, (Map<Id, Product2>) Trigger.oldMap);
        RES_PaymentPlanServices.tagReactivatedPlansToUnits((List<Product2>) Trigger.new, (Map<Id, Product2>) Trigger.oldMap);
        RES_UnitDraftCancellationService.handleUnitsMovedToDraft((List<Product2>) Trigger.new, (Map<Id, Product2>) Trigger.oldMap);
    }
}