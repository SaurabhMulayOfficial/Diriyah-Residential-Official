public with sharing class RES_MeasurementTriggerHandler extends RES_BaseTriggerHandler {
    public RES_MeasurementTriggerHandler() {}
    protected override void beforeInsert() {
        Date defaultTo = Date.newInstance(2099, 12, 31);
        for (RES_Measurement__c m : (List<RES_Measurement__c>) Trigger.new) {
            if (m.RES_Measurement_To__c == null) m.RES_Measurement_To__c = defaultTo;
        }
    }

    protected override void afterInsert(){
        List<RES_Measurement__c> newMeasurements = (List<RES_Measurement__c>) Trigger.new;

        // Only pass measurements to the service for units that already have a SAP ExternalId.
        // New units (ExternalId blank) are being INSERTed to SAP right now via Unit_Sync —
        // that payload already includes all measurements, so firing Measurement_Sync here
        // would duplicate the sync.
        Set<Id> productIds = new Set<Id>();
        for (RES_Measurement__c m : newMeasurements) {
            if (m.RES_Product__c != null) productIds.add(m.RES_Product__c);
        }

        Set<Id> productsWithExternalId = new Set<Id>();
        if (!productIds.isEmpty()) {
            for (Product2 p : [
                SELECT Id FROM Product2
                WHERE Id IN :productIds
                  AND RES_Product_External_ID__c != null
                  AND RES_Product_External_ID__c != ''
            ]) {
                productsWithExternalId.add(p.Id);
            }
        }

        List<RES_Measurement__c> measurementsForExistingUnits = new List<RES_Measurement__c>();
        for (RES_Measurement__c m : newMeasurements) {
            if (m.RES_Product__c == null || productsWithExternalId.contains(m.RES_Product__c)) {
                measurementsForExistingUnits.add(m);
            }
        }

        if (!measurementsForExistingUnits.isEmpty()) {
            RES_MeasurementServices.syncMeasurements(measurementsForExistingUnits, null);
        }
    }

    protected override void beforeUpdate() {
    }

    protected override void afterUpdate() {
        RES_MeasurementServices.syncMeasurements((List<RES_Measurement__c>) Trigger.new, (Map<Id, RES_Measurement__c>) Trigger.oldMap);
    }
}
