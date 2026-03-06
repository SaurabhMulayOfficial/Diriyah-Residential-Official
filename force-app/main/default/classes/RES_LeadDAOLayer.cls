/**
 * ==============================================================================
 * Class Name    : RES_LeadDAOLayer
 * Description   : Data Access Object (DAO) layer for the Lead object.
 *                 Provides standardized methods for querying and retrieving
 *                 Lead records within the application.
 * Author        : Rohan Jambhule
 * Company       : Globant Inc
 * Created Date  : Feb 23, 2026
 * Version       : 1.0
 *
 * Framework Rule:
 *      - All DAO layers must extend RES_BaseDAOLayer.
 *      - Each implementation must override getSObjectName()
 *        to specify the associated SObject.
 * ==============================================================================
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

    private static final String CLASS_NAME = 'RES_LeadDAOLayer';

    // =========================================================================
    // Specifies the SObject this DAO layer operates on.
    // Required by RES_BaseDAOLayer framework contract.
    // =========================================================================
    protected override String getSObjectName() {
        return 'Lead';
    }

    // =========================================================================
    // Returns a QueryLocator for batch processing of Lead records.
    // Fetches all Leads whose Status is NOT in the provided exclusion list,
    // restricted to RES_Company and RES_Individual RecordTypes.
    // Used by RES_LeadRetirementBatch to identify Leads eligible for retirement.
    //
    // @param  statusList  List of Status values to exclude from results
    // @return             QueryLocator for batch iteration
    // =========================================================================
    public Database.QueryLocator getLeadsForProcessingBatch(List<String> statusList) {
        Map<String,Object> bindVars = new Map<String,Object>();
        bindVars.put('statusList', statusList);
        String soql = 'SELECT Id, LastModifiedDate, CreatedDate, Status FROM Lead WHERE Status NOT IN :statusList AND (RecordType.DeveloperName = \'RES_Company\' OR RecordType.DeveloperName = \'RES_Individual\')';
        return executeBatchQuery(soql, bindVars, AccessLevel.USER_MODE);
    }

    // =========================================================================
    // Fetches Lead records by their IDs.
    // Restricted to RES_Company and RES_Individual RecordTypes to prevent
    // processing of unrelated Lead records.
    // Returns fields required for Lead conversion and SLA processing.
    //
    // @param  leadIds  Set of Lead record IDs to query
    // @return          List of matching Lead records, or empty list if none found
    // =========================================================================
    public List<Lead> getLeadsById(Set<Id> leadIds) {
        Map<String,Object> bindVars = new Map<String,Object>();
        bindVars.put('leadIds', leadIds);
        String soql = 'SELECT Id, Name, OwnerId, RES_SLA_Cycle_Count__c, RES_SLA_Breach_Time__c, RES_Previous_Lead_Owner__c FROM Lead WHERE Id IN :leadIds AND (RecordType.DeveloperName = \'RES_Company\' OR RecordType.DeveloperName = \'RES_Individual\')';
        return (List<Lead>) executeQuery(soql, '', false, bindVars, AccessLevel.USER_MODE);
    }

    // =========================================================================
    // Resolves the ApiName of a converted LeadStatus by its MasterLabel.
    // Used by RES_LeadMassConversionUtility to obtain the correct ApiName
    // required by Database.convertLead() — which does not accept MasterLabel.
    //
    // Example:
    //   Input  : 'Qualified'  (MasterLabel passed from Flow Custom Label)
    //   Output : '04'         (ApiName required by Database.convertLead())
    //
    // @param  statusLabel  MasterLabel of the target LeadStatus
    // @return              ApiName of the matching converted LeadStatus,
    //                      or null if no matching status is found
    // =========================================================================
    public String getConvertedStatusLabel(String statusLabel) {
        Map<String,Object> bindVars = new Map<String,Object>();
        bindVars.put('statusLabel', statusLabel);
        String soql = 'SELECT MasterLabel, ApiName FROM LeadStatus WHERE MasterLabel = :statusLabel AND IsConverted = true LIMIT 1';
        List<SObject> results = executeQuery(soql, '', false, bindVars, AccessLevel.USER_MODE);
        if (results == null || results.isEmpty()) {
            return null;
        }
        LeadStatus ls = (LeadStatus) results[0];
        return ls.ApiName;
    }
}