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
        String recordTypeDeveloperName = System.Label.RES_Product_Installment_RT;
        Map<String, Object> bindVars = new Map<String, Object>{
            'parentProductIds' => parentProductIds,
            'recordTypeDeveloperName' => recordTypeDeveloperName
        };
        String soql = 'SELECT Id, ParentProductId, ParentProduct.RES_Business_Entity__c, ChildProductId, Quantity, '+ 
                      'IsComponentRequired, IsDefaultComponent, IsQuantityEditable, DoesBundlePriceIncludeChild, '+ 
                      'QuoteVisibility, ChildProduct.RES_POC_Percentage__c, ChildProduct.RES_Installment_Percentage__c, '+ 
                      'ChildProduct.Name, ChildProduct.RecordTypeId, ChildProduct.RES_CIP_Type__c, ChildProduct.RES_Sequence__c, '+ 
                      'ChildProduct.ProductCode, ChildProduct.RES_Instalment_DueDate__c, ChildProduct.RES_Installment_Accumulative_Payments__c, '+ 
                      'ChildProduct.RES_Installment_Construction_Progress__c, ChildProduct.Description, ChildProduct.IsActive, '+ 
                      'ChildProduct.RES_Installment_Amount__c, ChildProduct.CurrencyIsoCode, ChildProduct.RES_Installment_Payment_Type__c, ' +
                      'ChildProduct.RES_Condition_Months__c, ChildProduct.RES_Condition_Days__c, ChildProduct.RES_Condition_Type__c ' +
                      'FROM ProductRelatedComponent ' +
                      'WHERE ParentProductId IN : parentProductIds AND ' +
                      'ChildProductId != NULL AND ' + 
                      'ChildProduct.RecordType.DeveloperName =: recordTypeDeveloperName ORDER BY ChildProduct.RES_Sequence__c ASC';
        
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
    
    /**
     * Retrieves every ProductRelatedComponent inside the named component group (the Unit's
     * "Payment Plan" group) for the given Units, together with each child Payment Plan's
     * active flag and validity end date. Ordered by Unit, then CreatedDate/Id so "first in
     * iteration" is stable between runs. Used by the Payment Plan expiry job to decide
     * which components to delete and which sibling becomes the new default.
     */
    public List<ProductRelatedComponent> getGroupComponentsByUnits(Set<Id> unitIds, String groupName) {
        if (unitIds == null || unitIds.isEmpty() || String.isBlank(groupName)) {
            return new List<ProductRelatedComponent>();
        }
        String soql =
            'SELECT Id, ParentProductId, ChildProductId, IsDefaultComponent, ' +
            'ChildProduct.Name, ChildProduct.IsActive, ChildProduct.RES_Validity_End_Date__c ' +
            'FROM ProductRelatedComponent ' +
            'WHERE ParentProductId IN :unitIds ' +
            'AND ProductComponentGroup.Name = :groupName ' +
            'ORDER BY ParentProductId, CreatedDate, Id';
        Map<String, Object> bindVars = new Map<String, Object>{
            'unitIds' => unitIds,
            'groupName' => groupName
        };
        return (List<ProductRelatedComponent>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Batch scope: Unit-level components (in the named group) whose child Payment Plan has a
     * validity end date strictly before the given date, i.e. plans that expired as of yesterday
     * or earlier.
     */
    public Database.QueryLocator getExpiredPaymentPlanComponentsLocator(Date today, String groupName) {
        String recordTypeDeveloperName = System.Label.RES_Product_Payment_Plan_RT;
        String soql =
            'SELECT Id, ParentProductId ' +
            'FROM ProductRelatedComponent ' +
            'WHERE ProductComponentGroup.Name = :groupName ' +
            'AND ChildProduct.RecordType.DeveloperName = :recordTypeDeveloperName ' +
            'AND ChildProduct.RES_Validity_End_Date__c < :today ' +
            'ORDER BY ParentProductId, Id';
        Map<String, Object> bindVars = new Map<String, Object>{
            'today' => today,
            'groupName' => groupName,
            'recordTypeDeveloperName' => recordTypeDeveloperName
        };
        return executeBatchQuery(soql, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public List<ProductRelatedComponent> getPaymentPlanAssignments(Set<Id> childProductIds) {
        if (childProductIds == null || childProductIds.isEmpty()) {
            return new List<ProductRelatedComponent>();
        }
        String recordTypeDeveloperName = System.Label.RES_Product_Payment_Plan_RT;
        Map<String, Object> bindVars = new Map<String, Object>{
            'childProductIds' => childProductIds,
            'recordTypeDeveloperName' => recordTypeDeveloperName
        };
        String soql = 'SELECT Id, ParentProductId, ParentProduct.RES_Business_Entity__c, ChildProductId, Quantity, '+ 
                      'IsComponentRequired, IsDefaultComponent, IsQuantityEditable, DoesBundlePriceIncludeChild, '+ 
                      'QuoteVisibility, ChildProduct.RES_POC_Percentage__c, ChildProduct.RES_Installment_Percentage__c, '+ 
                      'ChildProduct.Name, ChildProduct.RecordTypeId, ChildProduct.RES_CIP_Type__c, ChildProduct.RES_Sequence__c, '+ 
                      'ChildProduct.ProductCode, ChildProduct.RES_Instalment_DueDate__c, ChildProduct.RES_Installment_Accumulative_Payments__c, '+ 
                      'ChildProduct.RES_Installment_Construction_Progress__c, ChildProduct.Description, ChildProduct.IsActive, '+ 
                      'ChildProduct.RES_Installment_Amount__c, ChildProduct.CurrencyIsoCode, ChildProduct.RES_Installment_Payment_Type__c, ' +
                      'ChildProduct.RES_Condition_Months__c, ChildProduct.RES_Condition_Days__c, ChildProduct.RES_Condition_Type__c, ' +
                      'ParentProduct.RES_Business_Entity__r.Name, ParentProduct.RES_Construction_Phase__c, ParentProduct.RES_Company_Code__c, ParentProduct.RES_Product_External_ID__c, ParentProduct.RES_Business_Entity__r.RES_Business_Entity_Id__c ' +
                      'FROM ProductRelatedComponent ' +
                      'WHERE ChildProductId IN : childProductIds AND ' +
                      'ChildProductId != NULL AND ' + 
                      'ChildProduct.RecordType.DeveloperName =: recordTypeDeveloperName ORDER BY ChildProduct.RES_Sequence__c ASC';
        
        return (List<ProductRelatedComponent>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}