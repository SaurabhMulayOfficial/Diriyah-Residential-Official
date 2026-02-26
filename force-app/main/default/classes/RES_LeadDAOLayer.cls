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

    
}