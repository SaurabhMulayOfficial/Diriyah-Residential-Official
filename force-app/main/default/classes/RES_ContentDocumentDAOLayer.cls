/**
 * Class Name   : RES_ContentDocumentDAOLayer
 * Description  : Data Access Object (DAO) layer for the ContentDocument object.
 */
public without sharing class RES_ContentDocumentDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ContentDocument';
    }

    public List<ContentVersion> getPrimaryImagesByDocumentIds(Set<Id> docIds) {
        if (docIds == null || docIds.isEmpty()) {
            return new List<ContentVersion>();
        }
        Map<String, Object> bindVars = new Map<String, Object>{
            'docIds' => docIds
        };

        String soql = 'SELECT Id, ContentDocumentId FROM ContentVersion ' +
                      'WHERE ContentDocumentId IN :docIds ' +
                      'AND RES_Want_this_as_product_Image__c = true AND IsLatest = true';

        return (List<ContentVersion>) executeQuery(soql, '', false, bindVars, AccessLevel.USER_MODE);
    }
}