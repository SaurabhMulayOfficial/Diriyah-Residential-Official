/**
 * Class Name   : RES_Product_Approval_Config__mdt
 * Description  : Data Access Object (DAO) layer for the RES_Product_Approval_Config__mdt object.
 *                Provides standardized methods for querying and retrieving
 *                RES_Product_Approval_Config__mdt records within the application.
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
public with sharing class RES_ProductApprovalConfigDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'RES_Product_Approval_Config__mdt';
    }
    /**
     * Retrieves all active approval configurations.
     */
    public List<RES_Product_Approval_Config__mdt>getActiveConfigs() {
        String soql =
                    'SELECT ' +
                    'DeveloperName, ' +
                    'MasterLabel, ' +
                    'RES_Approval_Level__c, ' +
                    'RES_Current_Status__c, ' +
                    'RES_Next_Status__c, ' +
                    'RES_Custom_Permission__c, ' +
                    'RES_Queue_Label__c, ' +
                    'RES_Active__c, ' +
                    'RES_Final_Level__c ' +
                    'FROM RES_Product_Approval_Config__mdt ' +
                    'WHERE RES_Active__c = true ' +
                    'ORDER BY RES_Approval_Level__c ASC';

        return (List<RES_Product_Approval_Config__mdt>) 
        executeQuery(soql, 'activeProductApprovalConfigs', false, new Map<String, Object>(), AccessLevel.SYSTEM_MODE);
    }
}