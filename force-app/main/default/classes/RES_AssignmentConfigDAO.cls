/**
 * Class Name   : RES_AssignmentConfigDAO
 * Description  : Data Access Object (DAO) layer for the AssignmentConfig object.
 *                Provides standardized methods for querying and retrieving
 *                Lead records within the application.
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

public with sharing class RES_AssignmentConfigDAO extends RES_BaseDAOLayer {
    protected override String getSObjectName(){
        return 'RES_Assignment_Config__c';
    }


    public List<RES_Assignment_Config__c> getActiveAssignmentConfigs(Set<String> recordTypeNames){
        List<String> conditions = new List<String>();
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('recordTypeNames', recordTypeNames);
        String soql = 'SELECT Id, Name, RES_Record_Types__c, RES_Channel__c, RES_Queue__c ' +
                    'FROM RES_Assignment_Config__c ' +
                    'WHERE RES_Record_Types__c IN :recordTypeNames';
        
        return (List<RES_Assignment_Config__c>) executeQuery(soql, 'activeAssignmentConfigs', true, bindVars, AccessLevel.SYSTEM_MODE);
    }
}