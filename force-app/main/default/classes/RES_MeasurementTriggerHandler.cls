public with sharing class RES_MeasurementTriggerHandler extends RES_BaseTriggerHandler {
    public RES_MeasurementTriggerHandler() {}
    protected override void beforeInsert() {
        RES_MeasurementServices.setMeasurementDefaults((List<RES_Measurement__c>) Trigger.new);
    }

    protected override void afterInsert(){
        RES_MeasurementServices.syncMeasurements((List<RES_Measurement__c>) Trigger.new, null);
        RES_MeasurementServices.syncActiveMeasurementsToProduct((List<RES_Measurement__c>) Trigger.new, null);
    }

    protected override void beforeUpdate() {
    }

    protected override void afterUpdate() {
        RES_MeasurementServices.syncMeasurements((List<RES_Measurement__c>) Trigger.new, (Map<Id, RES_Measurement__c>) Trigger.oldMap);
        RES_MeasurementServices.syncActiveMeasurementsToProduct((List<RES_Measurement__c>) Trigger.new, (Map<Id, RES_Measurement__c>) Trigger.oldMap);
    }

    protected override void afterDelete() {
        RES_MeasurementServices.syncActiveMeasurementsToProduct((List<RES_Measurement__c>) Trigger.old, null);
    }

    protected override void afterUndelete() {
        RES_MeasurementServices.syncActiveMeasurementsToProduct((List<RES_Measurement__c>) Trigger.new, null);
    }
}