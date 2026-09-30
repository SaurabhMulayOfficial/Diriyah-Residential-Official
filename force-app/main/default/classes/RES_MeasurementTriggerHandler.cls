public with sharing class RES_MeasurementTriggerHandler extends RES_BaseTriggerHandler {
    public RES_MeasurementTriggerHandler() {}
    protected override void beforeInsert() {
        Date defaultTo = Date.newInstance(2099, 12, 31);
        for (RES_Measurement__c m : (List<RES_Measurement__c>) Trigger.new) {
            if (m.RES_Measurement_To__c == null) m.RES_Measurement_To__c = defaultTo;
        }
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
