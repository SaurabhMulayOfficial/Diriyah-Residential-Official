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

        List<RES_Integration_Request__e> integrationRequestEventList = new List<RES_Integration_Request__e>();
        Set<Id> unitProductIds = new Set<Id>();
        Set<Id> categoryIds = new Set<Id>();
        Set<Id> catalogIds = new Set<Id>();

        for(RES_Measurement__c m : measurementsToSync){
            if(m.RES_Category__c != null){
                categoryIds.add(m.RES_Category__c);
            }

            if(m.RES_Catalog__c != null){
                catalogIds.add(m.RES_Catalog__c);
            }

            if(m.RES_Product__c != null){
                unitProductIds.add(m.RES_Product__c);
            }
        }

        // Measurements travel as a child array of their Category / Catalog payload, so one event per unique parent.
        integrationRequestEventList.addAll(buildParentSyncEvents(categoryIds, catalogIds));

        String triggerContext = oldMap == null ? 'I' : 'U';
        for(Id productId : unitProductIds){
            RES_Integration_Request__e unitReq = new RES_Integration_Request__e();
            unitReq.RES_RecordIds__c = String.valueOf(productId);
            unitReq.RES_Request_Method__c = 'GET';
            unitReq.RES_Service_Name__c = 'Unit_Sync';
            unitReq.RES_Triggering_Context__c = triggerContext;
            integrationRequestEventList.add(unitReq);
        }

        try{
            EventBus.publish(integrationRequestEventList);
        }catch(Exception e){
            System.debug('Exception Firing Integration Request Event ' + e.getMessage());
        }
    }

    /**
     * @description Builds ProductCategory_Sync / ProductCatalog_Sync events for the given parents. The triggering context is
     *              per parent: never synced (RES_Last_Sync_DateTime__c null) → 'I', otherwise 'U'.
     */
    public static List<RES_Integration_Request__e> buildParentSyncEvents(Set<Id> categoryIds, Set<Id> catalogIds) {
        List<RES_Integration_Request__e> events = new List<RES_Integration_Request__e>();

        for (ProductCategory pc : new RES_ProductCategoryDAOLayer().getCategoriesByIds(categoryIds)) {
            events.add(buildParentEvent(pc.Id, 'ProductCategory_Sync', pc.RES_Last_Sync_DateTime__c));
        }

        for (ProductCatalog pc : new RES_ProductCatalogDAOLayer().getCatalogByIds(catalogIds)) {
            events.add(buildParentEvent(pc.Id, 'ProductCatalog_Sync', pc.RES_Last_Sync_DateTime__c));
        }

        return events;
    }

    private static RES_Integration_Request__e buildParentEvent(Id parentId, String serviceName, Datetime lastSync) {
        RES_Integration_Request__e req = new RES_Integration_Request__e();
        req.RES_RecordIds__c = String.valueOf(parentId);
        req.RES_Request_Method__c = 'GET';
        req.RES_Service_Name__c = serviceName;
        req.RES_Triggering_Context__c = lastSync == null ? 'I' : 'U';
        return req;
    }

    public static void setMeasurementDefaults(List<RES_Measurement__c> measurements) {
        Date defaultTo = Date.newInstance(2099, 12, 31);
        for (RES_Measurement__c m : measurements) {
            if (m.RES_Measurement_To__c == null) m.RES_Measurement_To__c = defaultTo;
        }
    }

    /**
     * @description Re-syncs RES_Active__c on the product's measurements and the measurement-derived Product2 fields (DIR-1797) for every product touched by the change:
     *              the current product, and the previous product when a measurement was re-parented or its values changed.
     * @param measurements Trigger.new (or Trigger.old for delete)
     * @param oldMap       Trigger.oldMap for update, null otherwise
     */
    public static void syncActiveMeasurementsToProduct(List<RES_Measurement__c> measurements, Map<Id, RES_Measurement__c> oldMap) {
        Set<Id> productIds = new Set<Id>();

        for (RES_Measurement__c m : measurements) {
            RES_Measurement__c old = oldMap == null ? null : oldMap.get(m.Id);
            if (old != null && !isActiveRelevantChange(m, old)) {
                continue;
            }
            if (m.RES_Product__c != null) {
                productIds.add(m.RES_Product__c);
            }
            if (old != null && old.RES_Product__c != null) {
                productIds.add(old.RES_Product__c);
            }
        }

        RES_ProductMeasurementSyncService.syncProducts(productIds);
    }

    private static Boolean isActiveRelevantChange(RES_Measurement__c n, RES_Measurement__c o) {
        return n.RES_Product__c != o.RES_Product__c
            || n.RES_Measurement_Type__c != o.RES_Measurement_Type__c
            || n.RES_Measurement_Amount__c != o.RES_Measurement_Amount__c
            || n.RES_Unit_Of_Measurement__c != o.RES_Unit_Of_Measurement__c
            || n.RES_Measurement_From__c != o.RES_Measurement_From__c
            || n.RES_Measurement_To__c != o.RES_Measurement_To__c;
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