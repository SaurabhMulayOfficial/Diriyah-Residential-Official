/**
* Class Name   : RES_ContentDocumentLinkDAOLayer
* Description  : Data Access Object (DAO) layer for the ContentDocumentLink object.
*                Provides standardized methods for querying and retrieving
*                ContentVersion records within the application.
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
public without sharing class RES_ContentVersionDAOLayer extends RES_BaseDAOLayer {
    /**
     * Returns the SObject API name handled by this DAO.
     * @return SObject API name.
     */
    protected override String getSObjectName() {
        return 'ContentVersion';
    }

    /**
     * Returns ContentVersion records by version Ids.
     *
     * @param versionIdSet latest published ContentVersion Ids.
     * @return list of ContentVersion records.
     */
    public List<ContentVersion> getContentVersionById(Set<Id> versionIdSet) {
        Map<String, Object> bindVars = new Map<String, Object>{
            'versionIdSet' => versionIdSet
        };

        String soql = 'SELECT Id, ContentDocumentId, Title, RES_Document_Label__c, ' +
            'RES_Attachment_Type__c, ContentSize, FileType, FileExtension, ' +
            'CreatedBy.Name, CreatedDate ' +
            'FROM ContentVersion ' +
            'WHERE Id IN :versionIdSet ' +
            'ORDER BY CreatedDate DESC';

        return (List<ContentVersion>) executeQuery(
            soql,
            '',
            false,
            bindVars,
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * Returns latest ContentVersion records for given ContentDocument Ids.
     *
     * @param documentIds ContentDocument Ids.
     * @return list of latest ContentVersion records.
     */
    public List<ContentVersion> getContentVersionToUpdate(Set<Id> documentIds) {
        Map<String, Object> bindVars = new Map<String, Object>{
            'documentIds' => documentIds
        };

        String soql = 'SELECT Id, ContentDocumentId, RES_Document_Label__c, ' +
            'RES_Attachment_Type__c ' +
            'FROM ContentVersion ' +
            'WHERE IsLatest = TRUE ' +
            'AND ContentDocumentId IN :documentIds';

        return (List<ContentVersion>) executeQuery(
            soql,
            '',
            false,
            bindVars,
            AccessLevel.SYSTEM_MODE
        );
    }
}