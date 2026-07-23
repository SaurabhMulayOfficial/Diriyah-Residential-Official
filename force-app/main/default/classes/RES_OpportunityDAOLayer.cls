/**
 * Class Name   : RES_OpportunityDAOLayer
 * Description  : Data Access Object (DAO) layer for the Opportunity object.
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
public without sharing class RES_OpportunityDAOLayer extends RES_BaseDAOLayer{
    protected override String getSObjectName() {
        return 'Opportunity';
    }
    public Opportunity getOpportunityById(Id opportunityId) {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('opportunityId', opportunityId);
        String soql = 'SELECT Id, Name, CloseDate, LeadSource, RES_Project__c, Owner.Name, ' +
                            'Account.Name ' +
                            'FROM Opportunity ' +
                            'WHERE Id = :opportunityId ' +
                            'LIMIT 1';
        List<SObject> results = executeQuery(soql, '', true, bindVars, AccessLevel.SYSTEM_MODE);
        return results != null && !results.isEmpty() ? (Opportunity) results[0] : null;
    }

    public List<Opportunity> getOpportunitiesRelatedToAccount(Id accountId){
        Map<String, Object> bindVars = new Map<String, Object>();
        Set<String> quoteStatusValues = new Set<String>{'Draft', 'Awaiting Client Confirmation', 'Negotiating'};
        String stageName = 'Proposal';
        bindVars.put('accountId', accountId);
        bindVars.put('stageName', stageName);
        bindVars.put('quoteStatusValues', quoteStatusValues);
        
        String soql = 'SELECT Id ' + 
                      'FROM Opportunity ' +
                      'WHERE Id IN ( ' +
                      'SELECT OpportunityId ' +
                      'FROM Quote ' +
                      'WHERE LineItemCount > 0 AND Status IN : quoteStatusValues ) AND ' +
                      'AccountId =: accountId AND ' + 
                      'StageName =: stageName';

        List<SObject> results = executeQuery(soql, '', true, bindVars, AccessLevel.SYSTEM_MODE);
        if(!results.isEmpty()){
            return results;
        }
        return null;
    }
}