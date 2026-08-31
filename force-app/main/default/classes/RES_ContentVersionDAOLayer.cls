/**
* Class Name   : RES_ContentVersionDAOLayer
* Description  : Data Access Object (DAO) layer for the ContentVersion object.
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
                     'AND FileType NOT IN (\'SNOTE\', \'LINK\') ' +
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
    
    /**
     * Returns latest ContentVersion records for given ContentDocument Ids.
     *
     * @param documentIds ContentDocument Ids.
     * @param attachmentType attachmentType.
     * @return list of latest ContentVersion records.
     */
    public List<ContentVersion> getContentVersionWithAttachmentType(Set<Id> documentIds, String attachmentType) {
        Map<String, Object> bindVars = new Map<String, Object>{
            'documentIds' => documentIds,
            'attachmentType' => attachmentType
        };

        String soql = 'SELECT Id ' +
                      'FROM ContentVersion ' +
                      'WHERE IsLatest = TRUE AND ' +
                      'ContentDocumentId IN : documentIds AND ' +
                      'RES_Attachment_Type__c =: attachmentType';

        return (List<ContentVersion>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Returns previous primary image ContentVersion records for related document Ids.
     *
     * @param relatedDocIds Set of related ContentDocument Ids.
     * @param currentCvIds Set of current transaction ContentVersion Ids to exclude.
     * @return list of ContentVersion records marked as primary image.
     */
    public List<ContentVersion> getPreviousPrimaryImages(Set<Id> relatedDocIds, Set<Id> currentCvIds) {
        if (relatedDocIds == null || relatedDocIds.isEmpty()) {
            return new List<ContentVersion>();
        }
        Map<String, Object> bindVars = new Map<String, Object>{
            'relatedDocIds' => relatedDocIds,
            'currentCvIds' => currentCvIds
        };

        String soql = 'SELECT Id, RES_Want_this_as_product_Image__c ' +
                      'FROM ContentVersion ' +
                      'WHERE ContentDocumentId IN :relatedDocIds ' +
                      'AND RES_Want_this_as_product_Image__c = true ' +
                      'AND Id NOT IN :currentCvIds';

        return (List<ContentVersion>) executeQuery(soql, '', false, bindVars, AccessLevel.USER_MODE);
    }
}