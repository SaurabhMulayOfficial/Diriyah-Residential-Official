/**
 * Class Name   : RES_AssignmentConditionsDAO
 * Description  : Data Access Object (DAO) layer for the Assignment Condition object.
 *                Provides standardized methods for querying and retrieving
 *                Assignment Condition records within the application.
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

public without sharing class RES_AssignmentConditionsDAO extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'RES_Assignment_Condition__c';
    }


    public List<RES_Assignment_Condition__c> getConditionsByConfigId(Set<Id> configIds){
        String soql =   'SELECT Id, RES_Field_Api_Name__c, RES_Operator__c, RES_Value__c, RES_Order__c, RES_Assignment_Config__c ' +
                        'FROM RES_Assignment_Condition__c ' +
                        'WHERE RES_Assignment_Config__c IN :configIds ' +
                        'ORDER BY RES_Order__c ASC';
        
        Map<String, Object> bindVars = new Map<String, Object>{'configIds' => configIds};
        return (List<RES_Assignment_Condition__c>) executeQuery(soql, 'getConditionsByConfigId', true, bindVars, AccessLevel.SYSTEM_MODE);
    }

}