/**
 * Class Name   : RES_ProductRelatedComponentDAOLayer
 * Description  : Data Access Object (DAO) layer for the
 *                ProductRelatedComponent object. Query-only, used by
 *                DIR-1258 bundle provisioning.
 *
 * Framework Rule:
 *      - All DAO layers must extend RES_BaseDAOLayer.
 *      - Each implementation must override getSObjectName()
 *        to specify the associated SObject.
 */
public without sharing class RES_ProductRelatedComponentDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ProductRelatedComponent';
    }

    /**
     * Retrieves existing ProductRelatedComponent rows linking the given
     * child (Payment Plan) product under any of the given parent (Unit)
     * products, so DIR-1258 bundle provisioning can skip units that already
     * have this exact Payment Plan wired in (idempotency on re-run).
     */
    public List<ProductRelatedComponent> getComponentsByParentProductsAndChild(Set<Id> parentProductIds, Id childProductId) {
        if (parentProductIds == null || parentProductIds.isEmpty() || childProductId == null) {
            return new List<ProductRelatedComponent>();
        }
        String soql =
            'SELECT Id, ParentProductId, ChildProductId ' +
            'FROM ProductRelatedComponent ' +
            'WHERE ParentProductId IN :parentProductIds ' +
            'AND ChildProductId = :childProductId';
        Map<String, Object> bindVars = new Map<String, Object>{
            'parentProductIds' => parentProductIds,
            'childProductId' => childProductId
        };
        return (List<ProductRelatedComponent>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}
