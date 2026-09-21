public with sharing class RES_MeasurementTriggerHandler extends RES_BaseTriggerHandler {
    public RES_MeasurementTriggerHandler() {}
    protected override void beforeInsert() {
    }

    protected override void afterInsert(){
        RES_MeasurementServices.syncMeasurements((List<RES_Measurement__c>) Trigger.new, null);
    }

    protected override void beforeUpdate() {
    }

    protected override void afterUpdate() {
        RES_MeasurementServices.syncMeasurements((List<RES_Measurement__c>) Trigger.new, (Map<Id, RES_Measurement__c>) Trigger.oldMap);
    }
}
