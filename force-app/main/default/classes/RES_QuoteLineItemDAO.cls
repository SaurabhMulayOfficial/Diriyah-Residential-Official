/**
 * Class Name   : RES_QuoteLineItemDAOLayer
 * Description  : Data Access Object (DAO) layer for the Quote Line Item object.
 *                Provides standardized methods for querying and retrieving
 *                Lead records within the application.
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
public Without sharing class RES_QuoteLineItemDAO extends RES_BaseDAOLayer {
    public RES_QuoteLineItemDAO() {}

    protected override String getSObjectName() {
        return 'QuoteLineItem';
    }

    public List<QuoteLineItem> getQuoteLineItemsByOpportunity(Set<Id> opportunityIds){

        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('opportunityIds', opportunityIds);

        Set<String> excludedStatuses = new Set<String>{'Expired', 'Cancelled'};
        bindVars.put('excludedStatuses', excludedStatuses);

        String soql = 'SELECT Id, QuoteId, Product2Id, Quote.OpportunityId, Quantity, UnitPrice, TotalPrice, Quote.IsSyncing ' +
                    'FROM QuoteLineItem ' +
                    'WHERE Quote.OpportunityId IN :opportunityIds ' +
                    'AND Quote.RES_Product_Soft_Held__c = false ' +
                    'AND Quote.Status NOT IN :excludedStatuses';

        return (List<QuoteLineItem>) executeQuery(
            soql,
            '',
            false,
            bindVars,
            AccessLevel.SYSTEM_MODE
        );
    }
    
    public List<QuoteLineItem> getQuoteLineItemsByProductIds(Set<Id> product2Ids){
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('product2Ids', product2Ids);

        String soql = 'SELECT Id, QuoteId, Quote.OpportunityId, Product2Id, Quantity, UnitPrice, TotalPrice ' +
                    'FROM QuoteLineItem ' +
                    'WHERE Product2Id IN :product2Ids AND Quote.RES_Product_Soft_Held__c = false';
        
        return (List<QuoteLineItem>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public List<QuoteLineItem> getQuoteLineItemsByQuoteIds(Set<Id> quoteIds){
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('quoteIds', quoteIds);

        String soql = 'SELECT Id, QuoteId, Product2.RES_Soft_Hold_Start__c, Product2Id, Product2.RES_Unit_Status__c, Product2.RES_Is_In_Soft_Hold_Extension__c, Product2.RES_Soft_Hold_Until__c, Product2.RES_Reserved_By_Quote__c ' +
                    'FROM QuoteLineItem ' +
                    'WHERE QuoteId IN :quoteIds';
        
        return (List<QuoteLineItem>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public List<QuoteLineItem> getQuoteLineItemsFiltered(Set<Id> quoteIds, Set<Id> productIds){
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('quoteIds', quoteIds);
        bindVars.put('productIds', productIds);

        String soql = 'SELECT Id, QuoteId, Product2Id ' +
                    'FROM QuoteLineItem ' +
                    'WHERE QuoteId NOT IN :quoteIds AND Product2Id IN :productIds';
        
        return (List<QuoteLineItem>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public List<QuoteLineItem> getActiveQuoteLineItemsByProductIdsExcludingOpportunities(
        Set<Id> productIds, Set<Id> excludedOpportunityIds
        ) {
            if (productIds == null || productIds.isEmpty()) {
                return new List<QuoteLineItem>();
            }
                Map<String, Object> bindVars = new Map<String, Object>();
                bindVars.put('productIds', productIds);
                bindVars.put('excludedOpportunityIds', excludedOpportunityIds);
            String soql = 'SELECT Id, Product2Id, Quote.OpportunityId, Quote.Status ' +
                            'FROM QuoteLineItem ' +
                            'WHERE Product2Id IN :productIds ' +
                            'AND Quote.OpportunityId NOT IN :excludedOpportunityIds ' +
                            'AND Quote.Status != \'Cancelled\'';
            return (List<QuoteLineItem>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
        }

}