/**
 * Class Name   : RES_ProductRelationshipTypeDAOLayer
 * Description  : Data Access Object (DAO) layer for the
 *                ProductRelationshipType object. Query-only, used by
 *                DIR-1258 bundle provisioning to resolve the standard
 *                "Bundle to Bundle Component Relationship" type Id at
 *                runtime rather than hardcoding it.
 *
 * Framework Rule:
 *      - All DAO layers must extend RES_BaseDAOLayer.
 *      - Each implementation must override getSObjectName()
 *        to specify the associated SObject.
 */
public without sharing class RES_ProductRelationshipTypeDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ProductRelationshipType';
    }

    /**
     * Retrieves the ProductRelationshipType record matching the given
     * Name (e.g. "Bundle to Bundle Component Relationship").
     */
    public ProductRelationshipType getByName(String relationshipTypeName) {
        if (String.isBlank(relationshipTypeName)) {
            return null;
        }
        String soql =
            'SELECT Id, Name ' +
            'FROM ProductRelationshipType ' +
            'WHERE Name = :relationshipTypeName ' +
            'LIMIT 1';
        Map<String, Object> bindVars = new Map<String, Object>{ 'relationshipTypeName' => relationshipTypeName };
        List<ProductRelationshipType> results =
            (List<ProductRelationshipType>) executeQuery(soql, 'byName_' + relationshipTypeName, true, bindVars, AccessLevel.SYSTEM_MODE);
        return results.isEmpty() ? null : results[0];
    }
}
