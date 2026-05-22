/**
 * Class Name   : RES_RoleFieldAccessDAO
 * Description  : Data Access Object (DAO) layer for the RES_Role_Field_Access__mdt object.
 *                Provides standardized methods for querying and retrieving
 *                RES_Role_Field_Access__mdt records within the application.
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

public with sharing class RES_RoleFieldAccessDAO extends RES_BaseDAOLayer {

    protected override String getSObjectName(){
        return 'RES_Role_Field_Access__mdt';
    }

    public List<RES_Role_Field_Access__mdt> getMetadataByRole(String userRole, String fieldApiName){
        Map<String,Object> bindVars = new Map<String, Object>();
        bindVars.put('userRole', userRole);
        bindVars.put('fieldApiName', fieldApiName);
        String soql = 'SELECT Id FROM RES_Role_Field_Access__mdt WHERE Role_API__c = :userRole AND Field_API__c = :fieldApiName LIMIT 1';
        return (List<RES_Role_Field_Access__mdt>) executeQuery(soql, 'getMetadataByRole', true, bindVars, AccessLevel.USER_MODE);
    }
}