/**
 * @description Controller for the integrationSync LWC. Fires one RES_Integration_Request__e
 *              Platform Event per record Id so each record is processed individually
 *              (no bulk support by design). Processing is asynchronous.
 */
public with sharing class RES_IntegrationSyncController {

    @TestVisible private static final Integer MAX_RECORDS = 200;
    private static final Set<String> VALID_METHODS = new Set<String>{ 'GET', 'POST', 'PATCH', 'PUT' };
    private static final Set<String> VALID_CONTEXTS = new Set<String>{ 'I', 'U' };
    private static final Set<String> VALID_SERVICES = new Set<String>{
        'Sales_Contract_Creation', 'Sales_Contract_Update', 'Sales_Contract_Termination',
        'Account_Sync', 'Unit_Sync', 'ProductCategory_Sync', 'ProductCatalog_Sync'
    };

    public class SyncResult {
        @AuraEnabled public Integer eventsFired;
        @AuraEnabled public List<String> invalidIds;
    }

    /**
     * @param serviceName   Service name as handled by RES_IntegrationQueueable
     * @param triggerContext I (Insert) or U (Update)
     * @param requestMethod GET, POST, PATCH or PUT
     * @param recordIds     One Id or comma/whitespace separated Ids
     */
    @AuraEnabled
    public static SyncResult fireIntegrationEvents(String serviceName, String triggerContext, String requestMethod, String recordIds) {
        if (!VALID_SERVICES.contains(serviceName)) {
            throw new AuraHandledException('Invalid service name.');
        }
        if (!VALID_CONTEXTS.contains(triggerContext)) {
            throw new AuraHandledException('Triggering context must be I or U.');
        }
        if (!VALID_METHODS.contains(requestMethod)) {
            throw new AuraHandledException('Invalid request method.');
        }

        Set<String> ids = new Set<String>();
        List<String> invalid = new List<String>();
        for (String raw : String.isBlank(recordIds) ? new List<String>() : recordIds.split('[,;\\s]+')) {
            String val = raw.trim();
            if (String.isBlank(val)) continue;
            if (isValidId(val)) {
                ids.add(val);
            } else {
                invalid.add(val);
            }
        }

        if (!invalid.isEmpty()) {
            throw new AuraHandledException('Invalid record Id(s): ' + String.join(invalid, ', '));
        }
        if (ids.isEmpty()) {
            throw new AuraHandledException('Please provide at least one record Id.');
        }
        if (ids.size() > MAX_RECORDS) {
            throw new AuraHandledException('A maximum of ' + MAX_RECORDS + ' record Ids is allowed per submit.');
        }

        List<RES_Integration_Request__e> events = new List<RES_Integration_Request__e>();
        for (String recId : ids) {
            events.add(new RES_Integration_Request__e(
                RES_RecordIds__c = recId,
                RES_Request_Method__c = requestMethod,
                RES_Triggering_Context__c = triggerContext,
                RES_Service_Name__c = serviceName
            ));
        }

        List<Database.SaveResult> results = EventBus.publish(events);
        Integer fired = 0;
        List<String> errors = new List<String>();
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                fired++;
            } else {
                for (Database.Error e : sr.getErrors()) errors.add(e.getMessage());
            }
        }
        if (fired == 0) {
            throw new AuraHandledException('Failed to publish events: ' + String.join(errors, '; '));
        }

        SyncResult res = new SyncResult();
        res.eventsFired = fired;
        res.invalidIds = errors;
        return res;
    }

    private static Boolean isValidId(String val) {
        if (val.length() != 15 && val.length() != 18) return false;
        try {
            Id.valueOf(val);
            return true;
        } catch (Exception e) {
            return false;
        }
    }
}
