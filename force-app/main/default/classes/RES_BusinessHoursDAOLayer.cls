/**
 * Class Name   : RES_BusinessHoursDAOLayer
 * Description  : Data Access Object (DAO) layer for the BusinessHours object.
 *                Provides standardized methods for querying and retrieving
 *                BusinessHours records within the application.
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

public with sharing class RES_BusinessHoursDAOLayer extends RES_BaseDAOLayer {
    public RES_BusinessHoursDAOLayer() {}

    protected override string getSObjectName(){
        return 'BusinessHours';
    } 
    /*
    * Query has been Utilized in RES_LeadRetirementBatch to fetch Business Hours.
    */

    public List<sObject> getDefaultBusinessHours(){
        String soql = 'SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1';
        List<SObject> results = executeQuery(soql, 'DefaultBusiness', true, null, AccessLevel.SYSTEM_MODE);
        return results;
    }

}