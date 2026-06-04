/**
* Class Name   : RES_ContentDocumentLinkDAOLayer
* Description  : Data Access Object (DAO) layer for the ContentDocumentLink object.
*                Provides standardized methods for querying and retrieving
*                ContentDocumentLink records within the application.
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
public without sharing class RES_ContentDocumentLinkDAOLayer extends RES_BaseDAOLayer {
    /**
     * Returns the SObject API name handled by this DAO.
     * @return Sobject API name.
     */
    protected override String getSObjectName() {
        return 'ContentDocumentLink';
    }

    /**
     * Returns ContentDocumentLink records for a linked record Id.
     *
     * @param linkedEntityId linked Salesforce record Id.
     * @return list of ContentDocumentLink records.
     */
    public List<ContentDocumentLink> getContentDocumentLinkByLinkedId(Id linkedEntityId) {
        Map<String, Object> bindVars = new Map<String, Object>{
            'linkedEntityId' => linkedEntityId
        };

        String soql = 'SELECT ContentDocument.LatestPublishedVersionId ' +
            'FROM ContentDocumentLink ' +
            'WHERE LinkedEntityId = :linkedEntityId ' +
            'ORDER BY ContentDocument.CreatedDate DESC';

        return (List<ContentDocumentLink>) executeQuery(
            soql,
            '',
            false,
            bindVars,
            AccessLevel.SYSTEM_MODE
        );
    }
}