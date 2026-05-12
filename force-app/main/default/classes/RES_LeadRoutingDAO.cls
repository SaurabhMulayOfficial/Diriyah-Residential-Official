/**
 * Class Name   : RES_LeadRoutingDAO
 * Description  : Data Access Object (DAO) layer for the Routing object.
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

public with sharing class RES_LeadRoutingDAO extends RES_BaseDAOLayer {

    protected override String getSObjectName() {
        return 'RES_Lead_Routing__c';
    }


    public List<RES_Lead_Routing__c> getRoutingRecordsByLeadIds(Set<Id> leadIds){
        if(leadIds.isEmpty()){
            return new List<RES_Lead_Routing__c>();
        }

        Map<String, Object> bindVars = new Map<String, Object>{
            'leadIds' => leadIds
        };

        String soql = 'SELECT Id, RES_Lead__c, RES_Assignment_Rule__c FROM RES_Lead_Routing__c ' +
                        'WHERE RES_Lead__c IN :leadIds';
        
        return (List<RES_Lead_Routing__c>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}