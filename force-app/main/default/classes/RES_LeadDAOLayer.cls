/**
 * Class Name   : RES_LeadDAOLayer
 * Description  : Data Access Object (DAO) layer for the Lead object.
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

public with sharing class RES_LeadDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'Lead';
    }
    private static final String CLASS_NAME = 'RES_LeadDAOLayer';
    /*
    * Used in RES_LeadRetirementBatch to fetch Leads for processing.
    */
    public Database.QueryLocator getLeadsForProcessingBatch(List<String> statusList){
        Map<String,Object> bindVars = new Map<String, Object> ();
        bindVars.put('statusList', statusList);
        String soql = 'SELECT Id, LastModifiedDate, CreatedDate, Status FROM Lead WHERE Status NOT IN :statusList AND (RecordType.DeveloperName = \'RES_Company\' OR RecordType.DeveloperName = \'RES_Individual\')';
        return executeBatchQuery(soql, bindVars, AccessLevel.USER_MODE);
    }

    public List<Lead> getLeadsById(Set<Id> leadIds) {
        Map<String,Object> bindVars = new Map<String, Object> ();
        bindVars.put('leadIds', leadIds);
        String soql = 'SELECT Id,Name, OwnerId FROM Lead WHERE Id IN :leadIds AND (RecordType.DeveloperName = \'RES_Company\' OR RecordType.DeveloperName = \'RES_Individual\')';
        return (List<Lead>) executeQuery(soql, '', false, bindVars, AccessLevel.USER_MODE);
    }

    public String getConvertedStatusLabel(String statusLabel) {
        Map<String,Object> bindVars = new Map<String,Object>();
        bindVars.put('statusLabel', statusLabel);
        String soql ='SELECT MasterLabel FROM LeadStatus WHERE MasterLabel = \'Qualified\' AND IsConverted = true LIMIT 1';
        List<SObject> results = executeQuery(soql,'convertedStatus',false,bindVars,AccessLevel.USER_MODE);
        if (results == null || results.isEmpty()) {
            return null;
        }
        String masterLabel = ((LeadStatus)results[0]).MasterLabel;
        return masterLabel;
    }
    
}