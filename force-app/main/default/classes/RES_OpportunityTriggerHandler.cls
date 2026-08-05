public without sharing class RES_OpportunityTriggerHandler extends RES_BaseTriggerHandler {
    public RES_OpportunityTriggerHandler() {}

    protected override void beforeInsert() {
    
    }
    protected override void beforeUpdate() {
    
    }

    protected override void afterInsert() {
    
    }

    protected override void afterUpdate() {
        RES_OpportunityServices.applySoftHoldOnProducts((List<Opportunity>) Trigger.new, (Map<Id, Opportunity>) Trigger.OldMap);
    }
}