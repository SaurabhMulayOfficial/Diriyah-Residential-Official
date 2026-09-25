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
     * parent (Unit) products matching the given Name, so DIR-1258 bundle
     * provisioning can skip units that already have the group.
     *
     * Deliberately matches on Name, not Code: Code is enforced globally
     * unique across the whole org on this object (confirmed against real
     * org data - "PP-01" on one Unit collides with any other Unit trying
     * to reuse it), so it cannot be used as a per-unit dedupe key. Name is
     * not globally unique and is what the existing bundle model already
     * reuses as "Payment Plan" across different Units.
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

    /**
     * Retrieves every ProductComponentGroup under the given parent products, regardless of
     * Name. Used by RES_ApplyApprovedPOCToFuturePaymentPlan to find each root Payment Plan's
     * existing Installments group, so the equivalent group on a new Payment Plan version can
     * mirror its Name/Sequence.
     */
    public List<ProductComponentGroup> getGroupsByParentProducts(Set<Id> parentProductIds) {
        if (parentProductIds == null || parentProductIds.isEmpty()) {
            return new List<ProductComponentGroup>();
        }
        String soql =
            'SELECT Id, ParentProductId, Name, Sequence, MinBundleComponents, MaxBundleComponents ' +
            'FROM ProductComponentGroup ' +
            'WHERE ParentProductId IN :parentProductIds';
        Map<String, Object> bindVars = new Map<String, Object>{ 'parentProductIds' => parentProductIds };
        return (List<ProductComponentGroup>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}