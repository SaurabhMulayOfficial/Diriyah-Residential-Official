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

        String soql = 'SELECT ContentDocument.LatestPublishedVersionId, ContentDocumentId ' +
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
    
    /**
     * Returns ContentDocumentLink records for a linked record Id.
     *
     * @param contentDocIds Salesforce record Ids.
     * @return list of ContentDocumentLink records.
     */
    public List<ContentDocumentLink> getContentDocumentLinkByContentDocumentId(Set<Id> contentDocIds) {
        Map<String, Object> bindVars = new Map<String, Object>{
            'contentDocIds' => contentDocIds
        };

        String soql = 'SELECT ContentDocument.Title, LinkedEntityId ' +
                      'FROM ContentDocumentLink ' +
                      'WHERE ContentDocumentId IN : contentDocIds';

        return (List<ContentDocumentLink>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Returns ContentDocumentLink records with ContentDocumentId and LinkedEntityId for document Ids.
     *
     * @param documentIds Set of ContentDocument Ids.
     * @return list of ContentDocumentLink records.
     */
    public List<ContentDocumentLink> getLinksByContentDocumentIds(Set<Id> documentIds) {
        if (documentIds == null || documentIds.isEmpty()) {
            return new List<ContentDocumentLink>();
        }
        Map<String, Object> bindVars = new Map<String, Object>{
            'documentIds' => documentIds
        };

        String soql = 'SELECT ContentDocumentId, LinkedEntityId ' +
                      'FROM ContentDocumentLink ' +
                      'WHERE ContentDocumentId IN :documentIds AND LinkedEntityId != NULL';

        return (List<ContentDocumentLink>) executeQuery(soql, '', false, bindVars, AccessLevel.USER_MODE);
    }

    /**
     * Returns ContentDocumentLink records linked to specific entity Ids.
     *
     * @param targetProductIds Set of target Product record Ids.
     * @return list of ContentDocumentLink records.
     */
    public List<ContentDocumentLink> getLinksByLinkedEntityIds(Set<Id> targetProductIds) {
        if (targetProductIds == null || targetProductIds.isEmpty()) {
            return new List<ContentDocumentLink>();
        }
        Map<String, Object> bindVars = new Map<String, Object>{
            'targetProductIds' => targetProductIds
        };

        String soql = 'SELECT ContentDocumentId ' +
                      'FROM ContentDocumentLink ' +
                      'WHERE LinkedEntityId IN :targetProductIds';

        return (List<ContentDocumentLink>) executeQuery(soql, '', false, bindVars, AccessLevel.USER_MODE);
    }
}