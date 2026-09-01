/**
 * Class Name   : RES_QuoteDAOLayer
 * Description  : Data Access Object (DAO) layer for the Quote object.
 *                Provides standardized methods for querying and retrieving
 *                Quote records within the application.
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
public with sharing class RES_QuoteDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'Quote';
    }
    public List<Quote> getQuotesByOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return new List<Quote>();
        }
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('opportunityIds', opportunityIds);

        String soql = 'SELECT Id, OpportunityId, Status FROM Quote WHERE OpportunityId IN :opportunityIds';
        return (List<Quote>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
    public Map<Id, Quote> getQuotesByIds(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return new Map<Id, Quote>();
        }
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('quoteIds', quoteIds);

        String soql = 'SELECT Id, Status FROM Quote WHERE Id IN :quoteIds';
        return new Map<Id, Quote>((List<Quote>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE));
    }
    public List<Quote> getQuotesByContractIds(Set<Id> contractIdSet, String status) {
        if (contractIdSet == null || contractIdSet.isEmpty()) {
            return new List<Quote>();
        }
        Boolean isSyncing = true;
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('contractIdSet', contractIdSet);
        bindVars.put('status', status);
        bindVars.put('isSyncing', isSyncing);

        String soql = 'SELECT Id, OpportunityId, ContractId ' +
        			  'FROM Quote ' + 
                      'WHERE ContractId IN :contractIdSet AND ' + 
                      'Status =: status AND ' +
                      'IsSyncing =: isSyncing';
        return (List<Quote>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}