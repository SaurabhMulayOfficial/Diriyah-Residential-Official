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
public with sharing class RES_QuoteLineItemDAO extends RES_BaseDAOLayer {
    public RES_QuoteLineItemDAO() {}

    protected override String getSObjectName() {
        return 'QuoteLineItem';
    }

    public List<QuoteLineItem> getQuoteLineItemsByOpportunity(Set<Id> OpportunityIds){
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('opportunityIds', opportunityIds);

        String soql = 'SELECT Id, QuoteId, Product2Id, Quote.OpportunityId, Quantity, UnitPrice, TotalPrice ' +
                    'FROM QuoteLineItem ' +
                    'WHERE Quote.OpportunityId IN :opportunityIds';
        
        return (List<QuoteLineItem>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
    
    public List<QuoteLineItem> getQuoteLineItemsByProductIds(Set<Id> product2Ids){
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('product2Ids', product2Ids);

        String soql = 'SELECT Id, QuoteId, Quote.OpportunityId, Product2Id, Quantity, UnitPrice, TotalPrice ' +
                    'FROM QuoteLineItem ' +
                    'WHERE Product2Id IN :product2Ids';
        
        return (List<QuoteLineItem>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}