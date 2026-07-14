/**
 * Class Name   : RES_FileTypeMdtDAO
 * Description  : Data Access Object (DAO) layer for the FileType__mdt object.
 *                Provides standardized methods for querying and retrieving
 *                FileType__mdt records within the application.
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


public without sharing class RES_FileTypeMdtDAO extends RES_BaseDAOLayer {

    protected override String getSObjectName() {
        return 'RES_File_Type__mdt';
    }

    public List<RES_File_Type__mdt> getFileTypesByObjectName(String objectName) {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('objectName', objectName);
        String soql = 'SELECT Id, developerName, RES_Object_Name__c, RES_File_Types__c FROM RES_File_Type__mdt WHERE RES_Object_Name__c = :objectName';
        return executeQuery(soql, 'getFileTypesByObjectName_' + objectName, true, bindVars, AccessLevel.SYSTEM_MODE);
    }

}