/**
 * @description Batch class that processes integration records one at a time,
 *              enqueuing a separate RES_IntegrationQueueable per record so that
 *              the external API (which does not support bulk payloads) receives
 *              exactly one record per callout.
 *
 *              Always execute with Database.executeBatch(..., 1) — the batch
 *              enforces scope size 1 internally but caller should also pass 1
 *              to avoid Salesforce combining chunks.
 *
 * Usage:
 *   Database.executeBatch(
 *       new RES_IntegrationAPIRouterBatch(records, 'Sales_Contract_Creation', 'GET', 'I'),
 *       1
 *   );
 */
public with sharing class RES_IntegrationAPIRouterBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {

    private List<SObject> allRecords;
    private String serviceName;
    private String requestMethod;
    private String triggeringContext;

    public RES_IntegrationAPIRouterBatch(
        List<SObject> records,
        String serviceName,
        String requestMethod,
        String triggeringContext
    ) {
        this.allRecords       = records;
        this.serviceName      = serviceName;
        this.requestMethod    = requestMethod;
        this.triggeringContext = triggeringContext;
    }

    public Iterable<SObject> start(Database.BatchableContext bc) {
        return allRecords;
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        List<SObject> singleRecord = new List<SObject>{ scope[0] };

        try {
            System.enqueueJob(
                new RES_IntegrationQueueable(
                    singleRecord,
                    serviceName,
                    requestMethod,
                    triggeringContext
                )
            );
        } catch (Exception e) {
            System.debug(
                '[RES_IntegrationAPIRouterBatch] Failed to enqueue job for record '
                + scope[0].Id + ': ' + e.getMessage()
            );
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(
            '[RES_IntegrationAPIRouterBatch] Batch complete | Service: ' + serviceName
            + ' | Method: ' + requestMethod + ' | Context: ' + triggeringContext
        );
    }
}