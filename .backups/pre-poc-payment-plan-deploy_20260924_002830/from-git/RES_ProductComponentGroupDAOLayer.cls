/**
 * Class Name   : RES_ProductComponentGroupDAOLayer
 * Description  : Data Access Object (DAO) layer for the ProductComponentGroup
 *                object. Query-only, used by DIR-1258 bundle provisioning.
 *
 * Framework Rule:
 *      - All DAO layers must extend RES_BaseDAOLayer.
 *      - Each implementation must override getSObjectName()
 *        to specify the associated SObject.
 */
public without sharing class RES_ProductComponentGroupDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ProductComponentGroup';
    }

    /**
     * Retrieves existing ProductComponentGroup records under the given
     */
    public List<ProductComponentGroup> getGroupsByParentProductsAndName(Set<Id> parentProductIds, String groupName) {
        if (parentProductIds == null || parentProductIds.isEmpty() || String.isBlank(groupName)) {
            return new List<ProductComponentGroup>();
        }
        String soql =
            'SELECT Id, ParentProductId, Name ' +
            'FROM ProductComponentGroup ' +
            'WHERE ParentProductId IN :parentProductIds ' +
            'AND Name = :groupName';
        Map<String, Object> bindVars = new Map<String, Object>{
            'parentProductIds' => parentProductIds,
            'groupName' => groupName
        };
        return (List<ProductComponentGroup>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}
