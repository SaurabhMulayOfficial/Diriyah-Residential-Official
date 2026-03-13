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

public without sharing class RES_LeadDAOLayer extends RES_BaseDAOLayer {
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
        String soql = 'SELECT Id,Name, Email, Phone, Company, RecordType.DeveloperName, OwnerId, RES_SLA_Cycle_Count__c, RES_SLA_Breach_Time__c, RES_Previous_Lead_Owner__c FROM Lead WHERE Id IN :leadIds AND (RecordType.DeveloperName = \'RES_Company\' OR RecordType.DeveloperName = \'RES_Individual\')';
        return (List<Lead>) executeQuery(soql, '', false, bindVars, AccessLevel.USER_MODE);
    }

    public String getConvertedStatusLabel(String statusLabel) {
        if (String.isBlank(statusLabel)) {
            return null;
        }
        Map<String,Object> bindVars = new Map<String,Object>();
        bindVars.put('statusLabel', statusLabel);
        String soql = 'SELECT MasterLabel, ApiName FROM LeadStatus WHERE MasterLabel = :statusLabel AND IsConverted = true ORDER BY MasterLabel ASC LIMIT 1';
        List<SObject> results = executeQuery(soql, '', false, bindVars, AccessLevel.USER_MODE);
        if (results == null || results.isEmpty()) {
            return null;
        }
        LeadStatus ls = (LeadStatus) results[0];
        return ls.ApiName;
    }

    public Map<Id, Lead> getLeadByIds(Set<Id> leadIds, Boolean useMap){
        Map<String, Object> bindVars = new Map<String, Object> ();
        bindVars.put('leadIds', leadIds);
        String soql = 'SELECT Id, Name, CreatedDate FROM Lead WHERE Id IN: leadIds';
        Map<Id, sObject> leadMap = executeQueryToMap(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
        Map<Id, Lead> typeCastedLeadMap = typeCast(leadMap);
        return typeCastedLeadMap;
    }

    public List<Lead> getLeadByEmailAndMobile(Set<String> Email, Set<String> Phone){
        String soql = 'SELECT Id, Email, MobilePhone, RES_Project__c, LeadSource FROM Lead WHERE Email IN:Email AND Phone IN:Phone ORDER BY CreatedDate DESC';
        Map<String,Object> bindVars = new Map<String, Object>();
        bindVars.put('Email', Email);
        bindVars.put('Phone', Phone);
        List<Lead> leads = (List<Lead>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
        return leads;
    }


    private Map<Id, Lead> typeCast(Map<Id, sObject> leadMap){
        Map<Id, Lead> newMap = new Map<Id, Lead>();
        for(Id key: leadMap.keySet()){
            Lead l = (Lead) leadMap.get(key);
            newMap.put(key, l);
        }

        return newMap;
    }


}