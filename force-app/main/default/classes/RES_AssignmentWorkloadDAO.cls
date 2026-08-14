/**
 * Class Name   : RES_AssignmentWorkloadDAO
 * Description  : Data Access Object (DAO) layer for the Assignment Workload object.
 *                Provides standardized methods for querying and retrieving
 *                Assignment Workload records within the application.
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
public without sharing class RES_AssignmentWorkloadDAO extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'RES_Assignment_Workload__c';
    }

    public Map<Id,RES_Assignment_Workload__c> getWorkloadById(Set<Id> workloadIds){
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('workloadIds', workloadIds);
        String soql = 'SELECT Id, RES_Active_Lead_Count__c, RES_Capacity__c, RES_User__c FROM RES_Assignment_Workload__c WHERE Id IN :workloadIds';
        Map<Id, sObject> result = executeQueryToMap(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
        Map<Id, RES_Assignment_Workload__c> workloadMap = new Map<Id, RES_Assignment_Workload__c>();
        for(Id key: result.keySet()){
            workloadMap.put(key, (RES_Assignment_Workload__c)result.get(key));
        }
        return workloadMap;
    }

    public List<RES_Assignment_Workload__c> getWorkloadByUserIds(Set<Id> userIds){
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('userIds', userIds);
        String soql = 'SELECT Id, RES_Active_Lead_Count__c, RES_Capacity__c, RES_User__c FROM RES_Assignment_Workload__c WHERE RES_User__c IN :userIds';
        return (List<RES_Assignment_Workload__c>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

}