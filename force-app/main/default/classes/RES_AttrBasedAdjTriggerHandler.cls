/**
 * @description Trigger handler for AttributeBasedAdjustment; delegates sync to RES_AttributeBasedAdjustmentService and refreshes units' default plan price.
 * @author      Roshan Jambhule
 * @date        2025
 */
public with sharing class RES_AttrBasedAdjTriggerHandler extends RES_BaseTriggerHandler {
    public RES_AttrBasedAdjTriggerHandler() {}

    protected override void beforeInsert() {}

    /** @description Publishes Unit_Sync events for products linked to newly inserted ABA records. */
    protected override void afterInsert() {
        RES_AttributeBasedAdjustmentService.syncUnits(
            (List<AttributeBasedAdjustment>) Trigger.new, null
        );
        RES_DefaultPlanPriceService.refresh(productIdsOf((List<AttributeBasedAdjustment>) Trigger.new, null));
    }

    protected override void beforeUpdate() {}

    /** @description Publishes Unit_Sync events for products linked to changed ABA records. */
    protected override void afterUpdate() {
        RES_AttributeBasedAdjustmentService.syncUnits(
            (List<AttributeBasedAdjustment>) Trigger.new,
            (Map<Id, AttributeBasedAdjustment>) Trigger.oldMap
        );
        RES_DefaultPlanPriceService.refresh(productIdsOf(
            (List<AttributeBasedAdjustment>) Trigger.new, (Map<Id, AttributeBasedAdjustment>) Trigger.oldMap
        ));
    }

    /** Products whose default plan price may change: inserted adjustments, or ones whose value/type/product/rule changed. */
    private static Set<Id> productIdsOf(List<AttributeBasedAdjustment> adjustments, Map<Id, AttributeBasedAdjustment> oldMap) {
        Set<Id> productIds = new Set<Id>();
        for (AttributeBasedAdjustment adjustment : adjustments) {
            AttributeBasedAdjustment old = oldMap?.get(adjustment.Id);
            if (old == null || old.AdjustmentValue != adjustment.AdjustmentValue || old.AdjustmentType != adjustment.AdjustmentType
                    || old.ProductId != adjustment.ProductId || old.AttributeBasedAdjRuleId != adjustment.AttributeBasedAdjRuleId) {
                if (adjustment.ProductId != null) {
                    productIds.add(adjustment.ProductId);
                }
                if (old?.ProductId != null) {
                    productIds.add(old.ProductId);
                }
            }
        }
        return productIds;
    }
}
