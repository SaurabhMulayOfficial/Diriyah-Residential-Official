 /**
  * @description Service layer for Measurement-related business operations.
  *              Provides reusable methods for processing and managing
  *              Measurement records.
  */
public with sharing class RES_MeasurementServices {

    public RES_MeasurementServices() {}

    public static void syncMeasurements(List<RES_Measurement__c> measurements, Map<Id, RES_Measurement__c> oldMap) {
        List<RES_Measurement__c> measurementsToSync = new List<RES_Measurement__c>();

        RES_SAP_Integration_Config__mdt measurementMDT =
            new RES_SAPIntegrationConfigDAO()
                .getSAPIntegrationConfigByDeveloperName('Measurement_Sync');

        if (measurementMDT == null || String.isBlank(measurementMDT.RES_Sync_Fields__c)) {
            throw new RES_IntegrationException(
                'SAP Integration Config is Not available for "Measurement", ' +
                'create and provide at least 1 field for change.'
            );
        }

        List<String> syncFieldLst = measurementMDT.RES_Sync_Fields__c.split(',');
        Set<String> syncFields = new Set<String>();
        for (String rawFieldName : syncFieldLst) {
            if (String.isNotBlank(rawFieldName)) {
                syncFields.add(rawFieldName.trim());
            }
        }

        for (RES_Measurement__c measurement : measurements) {
            if (oldMap == null || isMeasurementChanged(measurement,oldMap.get(measurement.Id),syncFields)) {
                measurementsToSync.add(measurement);
            }
        }

        if (measurementsToSync.isEmpty()) {
            return;
        }

        String triggerContext = oldMap == null ? 'I' : 'U';

        try {
            Id jobId = System.enqueueJob(
            new RES_IntegrationQueueable(
                measurementsToSync,
                'Measurement_Sync',
                'GET',
                triggerContext
                )
            );
            System.debug('Job Id for: Measurement_Sync ' + jobId);
        } catch (Exception e) {
            System.debug('Failed to Enqueue Job: SyncMeasurement ' + e.getMessage());
        }
    }

    private static Boolean isMeasurementChanged(RES_Measurement__c newMeasurement, RES_Measurement__c oldMeasurement, Set<String> syncFields) {
        if (oldMeasurement == null) {
            return true;
        }

        for (String fieldName : syncFields) {
            Object newValue = newMeasurement.get(fieldName);
            Object oldValue = oldMeasurement.get(fieldName);

            if (String.valueOf(newValue) != String.valueOf(oldValue)) {
                return true;
            }
        }

        return false;
    }

}