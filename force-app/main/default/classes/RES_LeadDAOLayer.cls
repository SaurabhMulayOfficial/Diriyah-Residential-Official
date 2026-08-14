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
        String soql = 'SELECT Id,Name, Email, Phone, LeadSource, Status, Company, RecordType.DeveloperName, OwnerId, RES_SLA_Cycle_Count__c, RES_SLA_Breach_Time__c, RES_Previous_Lead_Owner__c FROM Lead WHERE Id IN :leadIds AND (RecordType.DeveloperName = \'RES_Company\' OR RecordType.DeveloperName = \'RES_Individual\')';
        return (List<Lead>) executeQuery(soql, '', false, bindVars, AccessLevel.USER_MODE);
    }

    public List<Lead> getLeadsByIds_extended(Set<Id> leadIds){
        Map<String,Object> bindVars = new Map<String, Object> ();
        bindVars.put('leadIds', leadIds);
        List<String> fieldSet = new RES_ExtendedQueriesDAO().getExtendedQueriesByName('RES_Lead_Reassignment');
        String soql = 'SELECT ' + String.join(fieldSet, ', ') + ' FROM Lead WHERE Id IN :leadIds';
        return (List<Lead>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public String getConvertedStatusLabel(String statusLabel) {
        if (String.isBlank(statusLabel)) {
            return null;
        }
        Map<String,Object> bindVars = new Map<String,Object>();
        bindVars.put('statusLabel', statusLabel);
        String soql = 'SELECT MasterLabel, ApiName FROM LeadStatus WHERE MasterLabel = :statusLabel AND IsConverted = true ORDER BY MasterLabel ASC LIMIT 1';
        List<SObject> results = executeQuery(soql, 'getConvertedStatusLabel', true, bindVars, AccessLevel.USER_MODE);
        if (results == null || results.isEmpty()) {
            return null;
        }
        LeadStatus ls = (LeadStatus) results[0];
        System.debug('LeadStatus--->'+ls.ApiName);
        return ls.ApiName;
    }

    public Map<Id, Lead> getLeadByIds(Set<Id> leadIds, Boolean useMap){
        Map<String, Object> bindVars = new Map<String, Object> ();
        bindVars.put('leadIds', leadIds);
        String soql = 'SELECT Id, Name, CreatedDate, leadSource, OwnerId, Status, RES_Project__c FROM Lead WHERE Id IN: leadIds';
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

    public List<Lead> getLeadByOwnerIds(Set<Id> ownerIds){
        Map<String,Object> bindVars = new Map<String, Object>();
        bindVars.put('ownerIds', ownerIds);
        List<String> fieldSet = new RES_ExtendedQueriesDAO().getExtendedQueriesByName('RES_Lead_Reassignment');
        String soql = 'SELECT ' + String.join(fieldSet, ', ') + ' FROM Lead WHERE OwnerId IN :ownerIds';
        List<Lead> leadList = (List<Lead>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
        return leadList;
    }


    private Map<Id, Lead> typeCast(Map<Id, sObject> leadMap){
        Map<Id, Lead> newMap = new Map<Id, Lead>();
        for(Id key: leadMap.keySet()){
            Lead l = (Lead) leadMap.get(key);
            newMap.put(key, l);
        }

        return newMap;
    }

    public List<Lead> getLeadsBySLAStatus(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return new List<Lead>();
        }
        
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('leadIds', leadIds);
        
        String soql = 'SELECT Id, ' +
                                'Name, ' +
                                'Status, ' +
                                'RecordTypeId, ' +
                                'RES_SLA_Status__c, ' +
                                'RES_SLA_Due_Time__c, ' +
                                'RES_SLA_Cycle_Count__c, ' +
                                'RES_SLA_Start_Time__c, ' +
                                'RES_SLA_Breach_Time__c, ' +
                                'OwnerId, ' +
                                'Email, ' +
                                'MobilePhone, ' +
                                'LeadSource, ' +
                                'Company, ' +
                                'RecordType.DeveloperName ' +
                        'FROM Lead ' +
                        'WHERE Id IN :leadIds ' +
                        'AND (RecordType.DeveloperName = \'RES_Company\' ' +
                        'OR RecordType.DeveloperName = \'RES_Individual\')';
        
        List<Lead> results = (List<Lead>) executeQuery(soql, '', false, bindVars, AccessLevel.USER_MODE);
        return results;
    }
    
    public Database.QueryLocator getQualifiedLeadsForBatch(){
        // Status API name 04 Label = Qualified
        String soql = 'SELECT Id, Name, Company, IsConverted, RecordType.developerName FROM Lead WHERE IsConverted = false AND Status = \'04\' AND (RecordType.DeveloperName = \'RES_Company\' OR RecordType.DeveloperName = \'RES_Individual\')';
        return executeBatchQuery(soql, null, AccessLevel.USER_MODE);
    }
    
    public Database.QueryLocator getNewLeadsForBatch(){
        // Status API name 01 Label = New
        String soql = 'SELECT Id, Name, RES_SLA_Due_Time__c FROM Lead WHERE Status = \'01\' AND RES_SLA_Due_Time__c != null AND RES_SLA_Status__c = \'Running\' AND (RecordType.DeveloperName = \'RES_Company\' OR RecordType.DeveloperName = \'RES_Individual\')';
        return executeBatchQuery(soql, null, AccessLevel.USER_MODE);
    }

    public List<Lead> getConvertedLeads() {
        String soql =
            'SELECT Id,' +
            'Name,' +
            'OwnerId,' +
            'Owner.Name,' +
            'Status,' +
            'Company,' +
            'Email,' +
            'MobilePhone,' +
            'LeadSource,' +
            'ConvertedDate,' +
            'CreatedDate ' +
            'FROM Lead ' +
            'WHERE IsConverted = true ' +
            'ORDER BY ConvertedDate DESC ' +
            'LIMIT 50000';

        return (List<Lead>) executeQuery(
            soql,
            '',
            false,
            null,
            AccessLevel.SYSTEM_MODE
        );
    }

    public List<Lead> getConvertedLeadsByAccountId(Id accountId){
        if (accountId == null) {
            return new List<Lead>();
        }

        Set<Id> contactIds = new Set<Id>();

        for (Contact con : [
            SELECT Id
            FROM Contact
            WHERE AccountId = :accountId
        ]) {
            contactIds.add(con.Id);
        }

        Map<String,Object> bindVars = new Map<String,Object>();
        bindVars.put('accountId', accountId);
        bindVars.put('contactIds', contactIds);

        String soql =
            'SELECT Id,' +
            'Name,' +
            'Company,' +
            'Email,' +
            'MobilePhone,' +
            'Rating,' +
            'ConvertedDate,' +
            'ConvertedAccountId,' +
            'ConvertedContactId,' +
            'CreatedDate ' +
            'FROM Lead ' +
            'WHERE IsConverted = true ' +
            'AND (' +
            'ConvertedAccountId = :accountId ' +
            'OR ConvertedContactId IN :contactIds' +
            ') ' +
            'ORDER BY ConvertedDate DESC';

        return (List<Lead>) executeQuery(
            soql,
            '',
            false,
            bindVars,
            AccessLevel.SYSTEM_MODE
        );
    }

    public Lead getLeadPendingQualifiedFlag(Id leadId) {
        if (leadId == null) {
            return null;
        }

        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('leadId', leadId);

        String soql =
            'SELECT Id,' +
            'RES_Pending_Qualified_Review__c ' +
            'FROM Lead ' +
            'WHERE Id = :leadId ' +
            'LIMIT 1';

        List<SObject> results = executeQuery(
            soql,
            '',
            false,
            bindVars,
            AccessLevel.USER_MODE
        );

        return results.isEmpty()
            ? null
            : (Lead) results[0];
    }

    public Lead getConvertedLeadById(Id leadId){
        if (leadId == null) {
            return null;
        }

        Map<String,Object> bindVars = new Map<String,Object>();
        bindVars.put('leadId', leadId);

        String soql =
            'SELECT Id,' +
            'Name,' +
            'Status,' +
            'IsConverted,' +
            'ConvertedAccountId,' +
            'ConvertedContactId,' +
            'ConvertedOpportunityId,' +
            'LastModifiedById ' +
            'FROM Lead ' +
            'WHERE Id=:leadId ' +
            'AND IsConverted=true ' +
            'LIMIT 1';

        List<SObject> results = executeQuery(
            soql,
            '',
            false,
            bindVars,
            AccessLevel.USER_MODE
        );

        return results.isEmpty()
            ? null
            : (Lead) results[0];
    }
    
    public Account getAccountNameById(Id accountId) {
        if (accountId == null) {
            return null;
        }

        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('accountId', accountId);

        String soql =
            'SELECT Id, Name, PersonContactId ' +
            'FROM Account ' +
            'WHERE Id = :accountId ' +
            'LIMIT 1';

        List<SObject> results = executeQuery(
            soql,
            '',
            false,
            bindVars,
            AccessLevel.SYSTEM_MODE
        );

        if (results == null || results.isEmpty()) {
            return null;
        }

        return (Account) results[0];
    }
}