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

    public List<Opportunity> getOpportunitiesRelatedToAccount(Set<Id> accountIdSet){
        Map<String, Object> bindVars = new Map<String, Object>();
        Set<String> quoteStatusValues = new Set<String>{'Customer Approved'};
        Set<String> quoteRecordTypeNames = new Set<String>{System.Label.RES_Quote_Residential_Sales_RT};
        Set<String> recordTypeNames = new Set<String>{System.Label.RES_Opportunity_Single_Buyer_RT, System.Label.RES_Opportunity_Multi_Buyer_RT};
        String stageName = 'Unit Selected';
        Boolean isSyncing = true;
        
        bindVars.put('accountIdSet', accountIdSet);
        bindVars.put('stageName', stageName);
        bindVars.put('quoteStatusValues', quoteStatusValues);
        bindVars.put('recordTypeNames', recordTypeNames);
        bindVars.put('isSyncing', isSyncing);
		bindVars.put('quoteRecordTypeNames', quoteRecordTypeNames);
        
        String soql = 'SELECT Id, AccountId, ' +
            		  '(SELECT Id, Name, OpportunityId, Status, IsSyncing ' +
                      'FROM Quotes ' +
                      'WHERE Status =: quoteStatusValues AND ' +
                      'IsSyncing =: isSyncing AND ' +
                      'RecordType.DeveloperName =: quoteRecordTypeNames) ' +
                      'FROM Opportunity ' +
                      'WHERE AccountId =: accountIdSet AND ' +
                      'StageName =: stageName AND ' +
                      'RecordType.DeveloperName =: recordTypeNames';

        List<Opportunity> results = (List<Opportunity>) executeQuery(soql, '', true, bindVars, AccessLevel.SYSTEM_MODE);
        if(!results.isEmpty()){
            return results;
        }
        return null;
    }
}