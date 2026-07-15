/**
 * Class Name   : RES_ActtachmentTypeToFieldMappingDAO
 * Description  : Data Access Object (DAO) layer for the RES_Attachment_Type_To_Field_Mapping__mdt object.
 *                Provides standardized methods for querying and retrieving
 *                RES_Attachment_Type_To_Field_Mapping__mdt records within the application.
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


public without sharing class RES_ActtachmentTypeToFieldMappingDAO extends RES_BaseDAOLayer {

    protected override String getSObjectName() {
        return 'RES_Attachment_Type_To_Field_Mapping__mdt';
    }

    public List<RES_Attachment_Type_To_Field_Mapping__mdt> getAllMappings(){
        String soql = 'SELECT Id, MasterLabel, RES_JsonMapping__c, RES_Object_Name__c ' +
                        'FROM RES_Attachment_Type_To_Field_Mapping__mdt';

        return executeQuery(soql, 'getAllMappings', true, null, AccessLevel.SYSTEM_MODE);
    }

}