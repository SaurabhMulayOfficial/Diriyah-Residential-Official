/**
 * @description Trigger handler for AttributeBasedAdjustment; delegates sync to RES_AttributeBasedAdjustmentService.
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
    }

    protected override void beforeUpdate() {}

    /** @description Publishes Unit_Sync events for products linked to changed ABA records. */
    protected override void afterUpdate() {
        RES_AttributeBasedAdjustmentService.syncUnits(
            (List<AttributeBasedAdjustment>) Trigger.new,
            (Map<Id, AttributeBasedAdjustment>) Trigger.oldMap
        );
    }
}
