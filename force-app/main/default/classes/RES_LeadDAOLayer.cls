public with sharing class RES_LeadDAOLayer extends RES_BaseDAOLayer {

    public RES_LeadDAOLayer() {}

    protected override String getSObjectName() {
        return 'Lead';
    }

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
        String soql = 'SELECT Id FROM Lead WHERE Id IN :leadIds AND (RecordType.DeveloperName = \'RES_Company\' OR RecordType.DeveloperName = \'RES_Individual\')';
        return (List<Lead>) executeQuery(soql, '', false, bindVars, AccessLevel.USER_MODE);
    }

    public String getConvertedStatusLabel(String statusLabel) {
        Map<String,Object> bindVars = new Map<String,Object>();
        bindVars.put('statusLabel', statusLabel);
        String soql ='SELECT MasterLabel FROM LeadStatus WHERE MasterLabel = :statusLabel AND IsConverted = true LIMIT 1';
        List<SObject> results = executeQuery(soql,'convertedStatus',false,bindVars,AccessLevel.USER_MODE);
        if (results == null || results.isEmpty()) {
            return null;
        }
        return ((LeadStatus)results[0]).MasterLabel;
    }
    
}