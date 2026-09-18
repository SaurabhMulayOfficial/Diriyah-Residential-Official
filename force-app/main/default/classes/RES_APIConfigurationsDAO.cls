/**
 * Class Name   : RES_APIConfigurationsDAO
 * Description  : Data Access Object (DAO) layer for the API Configuration object.
 *                Provides standardized methods for querying and retrieving
 *                API Configuration records within the application.
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
public without sharing class RES_APIConfigurationsDAO extends RES_BaseDAOLayer {
    public RES_APIConfigurationsDAO() {}

    protected override String getSObjectName() {
        return 'RES_API_Configuration__mdt';
    }

    public List<RES_API_Configuration__mdt> getAPIConfiguration(String requestMethod, String apiName){
        Map<String,Object> bindVars = new Map<String,Object>();
        bindVars.put('requestMethod', requestMethod);
        bindVars.put('apiName', apiName);
        String soql = 'select Id, DeveloperName, RES_Endpoint__c, RES_Max_Retries__c, RES_Callout_Timeout__c, RES_Headers__c from RES_API_Configuration__mdt WHERE DeveloperName  =: apiName AND RES_Request_Method__c =: requestMethod';
        return executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}