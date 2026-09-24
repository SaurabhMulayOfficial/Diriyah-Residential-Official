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

    /**
     * Get Components By Parent Products. Ordered by the child Installment's own
     * RES_Sequence__c (not Name) since RES_ApplyApprovedPOCToFuturePaymentPlan relies on
     * this order to accumulate POC% and decide which installments merge.
     */
    public List<ProductRelatedComponent> getComponentsByParentProducts(Set<Id> parentProductIds) {
        if (parentProductIds == null || parentProductIds.isEmpty()) {
            return new List<ProductRelatedComponent>();
        }
        String soql = 'SELECT Id, ParentProductId, ParentProduct.RES_Business_Entity__c, ChildProductId, Quantity, IsComponentRequired, IsDefaultComponent, IsQuantityEditable, DoesBundlePriceIncludeChild, QuoteVisibility, ChildProduct.RES_POC_Percentage__c, ChildProduct.RES_Installment_Percentage__c, ChildProduct.Name, ChildProduct.RecordTypeId, ChildProduct.RES_CIP_Type__c, ChildProduct.RES_Sequence__c, ChildProduct.ProductCode, ChildProduct.RES_Instalment_DueDate__c, ChildProduct.RES_Installment_Accumulative_Payments__c, ChildProduct.RES_Installment_Construction_Progress__c, ChildProduct.Description, ChildProduct.IsActive, ChildProduct.RES_Installment_Amount__c, ChildProduct.CurrencyIsoCode ' +
                      'FROM ProductRelatedComponent ' +
                      'WHERE ParentProductId IN : parentProductIds AND ' +
                      'ChildProductId != NULL ORDER BY ChildProduct.RES_Sequence__c ASC';
        Map<String, Object> bindVars = new Map<String, Object>{
            'parentProductIds' => parentProductIds
        };
        return (List<ProductRelatedComponent>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Retrieves ProductRelatedComponent rows whose ChildProductId is one of the given
     * (Unit-level) Payment Plan products - i.e. the rows wiring Units to a Payment Plan.
     * Used by RES_ApplyApprovedPOCToFuturePaymentPlan to repoint each Unit's existing
     * component at a newly-approved Payment Plan version.
     */
    public List<ProductRelatedComponent> getComponentsByChildProducts(Set<Id> childProductIds) {
        if (childProductIds == null || childProductIds.isEmpty()) {
            return new List<ProductRelatedComponent>();
        }
        String soql = 'SELECT Id, ParentProductId, ChildProductId, ProductComponentGroupId, ProductRelationshipTypeId, Quantity, IsComponentRequired, IsDefaultComponent, IsQuantityEditable, DoesBundlePriceIncludeChild, QuoteVisibility, RES_Price_Option__c ' +
                      'FROM ProductRelatedComponent ' +
                      'WHERE ChildProductId IN :childProductIds';
        Map<String, Object> bindVars = new Map<String, Object>{ 'childProductIds' => childProductIds };
        return (List<ProductRelatedComponent>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}