/**
  * @description Service layer for Measurement-related business operations.
  *              Provides reusable methods for processing and managing
  *              Measurement records.
  */
public with sharing class RES_MeasurementServices {

    // Allows tests to force the catalog sync path without needing a live MDT record.
    @TestVisible private static Boolean forceCatalogSyncEnabled = null;

    public RES_MeasurementServices() {}

    public static void syncMeasurements(List<RES_Measurement__c> measurements, Map<Id, RES_Measurement__c> oldMap) {
        List<RES_Measurement__c> measurementsToSync = new List<RES_Measurement__c>();

        RES_SAPIntegrationConfigDAO configDao = new RES_SAPIntegrationConfigDAO();

        RES_SAP_Integration_Config__mdt measurementMDT =
            configDao.getSAPIntegrationConfigByDeveloperName('Measurement_Sync');

        if (measurementMDT == null || String.isBlank(measurementMDT.RES_Sync_Fields__c)) {
            throw new RES_IntegrationException(
                'SAP Integration Config is Not available for "Measurement", ' +
                'create and provide at least 1 field for change.'
            );
        }

        // Catalog measurement sync is enabled only when a Measurement_Sync_Catalog MDT record exists.
        // Remove/disable the record to suppress until the Product_Catalog_API endpoint is fixed by SAP.
        Boolean catalogSyncEnabled = forceCatalogSyncEnabled != null ? forceCatalogSyncEnabled
            : configDao.getSAPIntegrationConfigByDeveloperName('Measurement_Sync_Catalog') != null;

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
        Set<Id> unitProductIds = new Set<Id>();

        for (RES_Measurement__c m : measurementsToSync) {
            if (m.RES_Product__c != null) unitProductIds.add(m.RES_Product__c);
        }

        // On INSERT: suppress Measurement_Sync/Catalog events for units that have no SAP ExternalId yet.
        // Unit_Sync INSERT is already in-flight and includes measurements in its payload.
        // RES_ProductIntegrationService.syncProducts re-fires these events once ExternalId is assigned.
        Map<Id, Boolean> unitHasExternalId = new Map<Id, Boolean>();
        if (oldMap == null && !unitProductIds.isEmpty()) {
            for (Product2 p : [SELECT Id, RES_Product_External_ID__c FROM Product2 WHERE Id IN :unitProductIds]) {
                unitHasExternalId.put(p.Id, String.isNotBlank(p.RES_Product_External_ID__c));
            }
        }

        for(RES_Measurement__c m : measurementsToSync){
            Boolean isNewUnitWithoutExtId = (oldMap == null)
                && m.RES_Product__c != null
                && unitHasExternalId.containsKey(m.RES_Product__c)
                && !unitHasExternalId.get(m.RES_Product__c);

            if (!isNewUnitWithoutExtId) {
                if(m.RES_Category__c != null){
                    RES_Integration_Request__e req = new RES_Integration_Request__e();
                    req.RES_RecordIds__c = String.valueOf(m.Id);
                    req.RES_Request_Method__c = 'GET';
                    req.RES_Service_Name__c = 'Measurement_Sync';
                    req.RES_Triggering_Context__c = triggerContext;
                    integrationRequestEventList.add(req);
                }

                if(m.RES_Catalog__c != null && catalogSyncEnabled){
                    RES_Integration_Request__e catalogReq = new RES_Integration_Request__e();
                    catalogReq.RES_RecordIds__c = String.valueOf(m.Id);
                    catalogReq.RES_Request_Method__c = 'GET';
                    catalogReq.RES_Service_Name__c = 'Measurement_Sync_Catalog';
                    catalogReq.RES_Triggering_Context__c = triggerContext;
                    integrationRequestEventList.add(catalogReq);
                }
            }
        }

        for(Id productId : unitProductIds){
            // Skip Unit_Sync re-trigger for units without ExternalId — their INSERT is already in-flight from afterInsert.
            Boolean skipUnitSync = (oldMap == null)
                && unitHasExternalId.containsKey(productId)
                && !unitHasExternalId.get(productId);
            if (!skipUnitSync) {
                RES_Integration_Request__e unitReq = new RES_Integration_Request__e();
                unitReq.RES_RecordIds__c = String.valueOf(productId);
                unitReq.RES_Request_Method__c = 'GET';
                unitReq.RES_Service_Name__c = 'Unit_Sync';
                unitReq.RES_Triggering_Context__c = triggerContext;
                integrationRequestEventList.add(unitReq);
            }
        }

        try{
            if (!integrationRequestEventList.isEmpty()) {
                EventBus.publish(integrationRequestEventList);
            }
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