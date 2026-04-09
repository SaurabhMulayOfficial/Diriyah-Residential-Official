/**
 * Class Name   : RES_LeadDeduplicationDAOLayer
 * Description  : Data Access Object (DAO) layer for the Lead_Deduplication_Rule__mdt object.
 *                Provides standardized methods for querying and retrieving
 *                Lead_Deduplication_Rule__mdt records within the application.
 *
 * Framework Rule:
 *      - All DAO layers must extend RES_BaseDAOLayer.
 *      - Each implementation must override getSObjectName()
 *        to specify the associated SObject.
 */

/**
 * =============================================================================
 * QUERY EXECUTION GUIDELINES
 * =============================================================================
 *
 * 1. Standard Query Execution
 *    Method:
 *      executeQuery(String soql,
 *                   String cacheSuffix,
 *                   Boolean useCache,
 *                   Map<String, Object> bindVars,
 *                   AccessLevel accessLevel)
 * 
 *    To get Map<id, Sobject> use executeQueryToMap(<Same Params as above>).
 * 
 *    Usage Guidelines:
 *      - Enable caching ONLY for static queries where data does not change frequently.
 *      - For dynamic queries:
 *            • Set useCache = false
 *            • Set cacheSuffix = ''
 *
 * 2. Batch Query Execution
 *    Method:
 *      executeBatchQuery(String soql,
 *                        Map<String, Object> bindVars,
 *                        AccessLevel accessLevel)
 * =============================================================================
 */

public without sharing class RES_LeadDeduplicationDAOLayer extends RES_BaseDAOLayer {

    protected override String getSObjectName() {
        return 'Lead_Deduplication_Rule__mdt';
    }

    public List<Lead_Deduplication_Rule__mdt> getAllRules(){
        String soql = 'SELECT Action__c, Lead_Age_Threshold_Days__c, Check_Field_Equality__c, Lead_Status__c, Assigned_To__c, Scenarios__c, Source__c FROM Lead_Deduplication_Rule__mdt';
        return (List<Lead_Deduplication_Rule__mdt>) executeQuery(soql, 'getAllRules', true, null, AccessLevel.SYSTEM_MODE);
    }
    
}