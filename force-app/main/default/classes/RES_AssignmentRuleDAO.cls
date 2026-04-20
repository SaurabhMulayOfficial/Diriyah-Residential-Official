/**
 * Class Name   : RES_AssignmentRuleDAO
 * Description  : Data Access Object (DAO) layer for the AssignmentRule object.
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

public with sharing class RES_AssignmentRuleDAO extends RES_BaseDAOLayer {
    protected override String getSObjectName(){
        return 'RES_Assignment_Rule__c';
    }

    public Map<Id, List<RES_Assignment_Rule__c>> getAssignmentRuleByConfig(Set<Id> configIds){
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('configIds', configIds);
        String soql = 'SELECT Id, Name, RES_User__c, RES_Lead_Count__c, ' +
              'RES_Assignment_Config__c, RES_Capacity__c, RES_Last_Assigned__c, ' +
              'RES_Order__c, RES_User_Availability_Status__c ' +
              'FROM RES_Assignment_Rule__c ' +
              'WHERE RES_Assignment_Config__c IN :configIds ' +
              'AND RES_User_Availability_Status__c = \'Available\' ' +
              'ORDER BY RES_Order__c ASC';
              
        List<RES_Assignment_Rule__c> rules = (List<RES_Assignment_Rule__c>) executeQuery(soql, 'assignmentRulesByConfig', true, bindVars, AccessLevel.SYSTEM_MODE);
        Map<Id, List<RES_Assignment_Rule__c>> ruleMap = new Map<Id, List<RES_Assignment_Rule__c>>();
        for(RES_Assignment_Rule__c rule : rules){
            if(!ruleMap.containsKey(rule.RES_Assignment_Config__c)){
                ruleMap.put(rule.RES_Assignment_Config__c, new List<RES_Assignment_Rule__c>());
            }

            ruleMap.get(rule.RES_Assignment_Config__c).add(rule);
        }
        return ruleMap;
    }


} 