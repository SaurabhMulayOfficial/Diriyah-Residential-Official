/**
 * @description Service layer for handling RES_Integration_Request__e Platform Events.
 *              Groups integration requests by service, request method, and triggering
 *              context, collects and deduplicates record IDs, retrieves the required
 *              records through the appropriate DAO layer, and enqueues the integration
 *              Queueable for asynchronous processing.
 *
 *              This service decouples trigger execution from integration processing
 *              by using Platform Events as the integration request mechanism.
 */

public with sharing class RES_IntegrationRequestEventService {

    private static final String PRODUCT_CATEGORY_INTEGRATION = 'ProductCategory_Sync';
    private static final String MEASUREMENT_INTEGRATION = 'Measurement_Sync';
    
    public RES_IntegrationRequestEventService() {}

    public static void handleIntegrations(List<RES_Integration_Request__e> requests){
        Map<String, List<RES_Integration_Request__e>> results = new Map<String, List<RES_Integration_Request__e>>();

        for(RES_Integration_Request__e req: requests){
            String key = (req.RES_Request_Method__c + req.RES_Service_Name__c + req.RES_Triggering_Context__c);
            if(!results.containsKey(key)){
                results.put(key, new List<RES_Integration_Request__e>());
            }
            results.get(key).add(req);
        }

        String pcIntegrationKey_onInsert = 'GET' + PRODUCT_CATEGORY_INTEGRATION + 'I';
        String pcIntegrationKey_onUpdate = 'GET' + PRODUCT_CATEGORY_INTEGRATION + 'U';

        if(results.containsKey(pcIntegrationKey_onInsert) && results.get(pcIntegrationKey_onInsert).size() > 0){
            Set<Id> pcIds = new Set<Id>();
            for(RES_Integration_Request__e e: results.get(pcIntegrationKey_onInsert)){
                if(String.isBlank(e.RES_RecordIds__c))continue;
                for (String recordId : e.RES_RecordIds__c.split(',')) {
                    if (String.isNotBlank(recordId)) {
                        pcIds.add((Id) recordId.trim());
                    }
                }
            }

            if(!pcIds.isEmpty()){
                List<sObject> records = (List<sObject> )new RES_ProductCategoryDAOLayer().getCategoriesByIds(pcIds);
                enqueueService(PRODUCT_CATEGORY_INTEGRATION, records, 'I', 'GET');
            }
        }

        if(results.containsKey(pcIntegrationKey_onUpdate) && results.get(pcIntegrationKey_onUpdate).size() > 0){
            Set<Id> pcIds = new Set<Id>();
            for(RES_Integration_Request__e e: results.get(pcIntegrationKey_onUpdate)){
                if(String.isBlank(e.RES_RecordIds__c))continue;
                for (String recordId : e.RES_RecordIds__c.split(',')) {
                    if (String.isNotBlank(recordId)) {
                        pcIds.add((Id) recordId.trim());
                    }
                }
            }

            if(!pcIds.isEmpty()){
                List<sObject> records = (List<sObject> )new RES_ProductCategoryDAOLayer().getCategoriesByIds(pcIds);
                enqueueService(PRODUCT_CATEGORY_INTEGRATION, records, 'U', 'GET');
            }
        }

        String measurementIntegrationKey_onInsert = 'GET' + MEASUREMENT_INTEGRATION + 'I';
        String measurementIntegrationKey_onUpdate = 'GET' + MEASUREMENT_INTEGRATION + 'U';

        if(results.containsKey(measurementIntegrationKey_onInsert) && results.get(measurementIntegrationKey_onInsert).size() > 0){
            Set<Id> measurementIds = new Set<Id>();
            for(RES_Integration_Request__e e: results.get(measurementIntegrationKey_onInsert)){
                if(String.isBlank(e.RES_RecordIds__c))continue;
                for (String recordId : e.RES_RecordIds__c.split(',')) {
                    if (String.isNotBlank(recordId)) {
                        measurementIds.add((Id) recordId.trim());
                    }
                }
            }

            if(!measurementIds.isEmpty()){
                List<sObject> records = (List<sObject>)new RES_MeasurementDAOLayer().getMeasurementByIds(measurementIds);
                enqueueService(MEASUREMENT_INTEGRATION, records, 'I', 'GET');
            }
        }

        if(results.containsKey(measurementIntegrationKey_onUpdate) && results.get(measurementIntegrationKey_onUpdate).size() > 0){
            Set<Id> measurementIds = new Set<Id>();
            for(RES_Integration_Request__e e: results.get(measurementIntegrationKey_onUpdate)){
                if(String.isBlank(e.RES_RecordIds__c))continue;

                for (String recordId : e.RES_RecordIds__c.split(',')) {
                    if (String.isNotBlank(recordId)) {
                        measurementIds.add((Id) recordId.trim());
                    }
                }
            }

            if(!measurementIds.isEmpty()){
                List<sObject> records = (List<sObject>)new RES_MeasurementDAOLayer().getMeasurementByIds(measurementIds);
                enqueueService(MEASUREMENT_INTEGRATION, records, 'U', 'GET');
            }
        }
    }

    public static void enqueueService(String serviceName, List<sObject> records, String triggeringContext, String requestMethod){
        if(String.isNotBlank(serviceName) && !records.isEmpty() && String.isNotBlank(triggeringContext) &&  String.isNotBlank(requestMethod)){
            try{
                Id jobId = System.enqueueJob(
                    new RES_IntegrationQueueable(
                        records,
                        serviceName,
                        requestMethod,
                        triggeringContext
                    )
                );
                System.debug('Job Sync ID ' + jobId);
            }catch(Exception e){
                System.debug('Failed to Enqueue Job ' + e.getMessage());
            }
        }
    }
}