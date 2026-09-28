/**
 * @description Trigger handler for ProductAttributeDefinition; delegates sync to RES_ProductAttributeDefinitionService.
 * @author      Roshan Jambhule
 * @date        2025
 */
public with sharing class RES_ProdAttrDefTriggerHandler extends RES_BaseTriggerHandler {
    public RES_ProdAttrDefTriggerHandler() {}

    protected override void beforeInsert() {}

    /** @description Publishes Unit_Sync events for products linked to newly inserted PAD records. */
    protected override void afterInsert() {
        RES_ProductAttributeDefinitionService.syncUnits(
            (List<ProductAttributeDefinition>) Trigger.new, null
        );
    }

    protected override void beforeUpdate() {}

    /** @description Publishes Unit_Sync events for products linked to changed PAD records. */
    protected override void afterUpdate() {
        RES_ProductAttributeDefinitionService.syncUnits(
            (List<ProductAttributeDefinition>) Trigger.new,
            (Map<Id, ProductAttributeDefinition>) Trigger.oldMap
        );
    }
}
