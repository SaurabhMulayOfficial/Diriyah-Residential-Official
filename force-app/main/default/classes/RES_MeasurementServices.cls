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

        List<RES_Integration_Request__e> integrationRequestEventList = new List<RES_Integration_Request__e>();        
        Set<String> recordIds = new Set<String>();
        for (RES_Measurement__c measurement : measurementsToSync) {
            recordIds.add(measurement.Id);
        }

        String recordIdsString = String.join(
            new List<String>(recordIds),
            ','
        );

        try{
            EventBus.publish(new RES_Integration_Request__e(
                RES_RecordIds__c = recordIdsString,
                RES_Request_Method__c = 'GET',
                RES_Service_Name__c = 'Measurement_Sync',
                RES_Triggering_Context__c = triggerContext
            ));
        }catch(Exception e){
            System.debug('Exception Firing Integration Request Event ' + e.getMessage());
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