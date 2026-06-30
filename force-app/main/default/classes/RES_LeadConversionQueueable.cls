/**
 * ==============================================================================
 * Class Name    : RES_LeadConversionQueueable
 * Description   : Queueable class to handle asynchronous Lead conversion with
 *                 SLA status polling. Ensures that backend automation flows
 *                 complete (RES_SLA_Status__c = 'Met') before attempting
 *                 lead conversion.
 *
 * Author        : Roshan Jambhule
 * Company       : Globant Inc
 * Created Date  : June 26, 2026
 * Version       : 2.2 (Refactored - Retry Handler Delegation)
 * ==============================================================================
 */
public with sharing class RES_LeadConversionQueueable implements Queueable {
    
    private List<Lead> qualifiedLeads;
    private Integer retryCount = 0;
    private static final String CLASS_NAME = 'RES_LeadConversionQueueable';

    public RES_LeadConversionQueueable(List<Lead> leads, Integer retries) {
        this.qualifiedLeads = leads;
        this.retryCount = retries;
    }

    public RES_LeadConversionQueueable(List<Lead> leads) {
        this.qualifiedLeads = leads;
        this.retryCount = 0;
    }

    public void execute(QueueableContext context) {
        try {            
            Set<Id> leadIds = new Set<Id>();
            for (Lead l : qualifiedLeads) {
                leadIds.add(l.Id);
            }
            
            List<Lead> freshLeads = requeryleads(leadIds);
            if (freshLeads == null || freshLeads.isEmpty()) {
                return;
            }
            
            if (checkAllLeadsReady(freshLeads)) {
                this.qualifiedLeads = freshLeads;
                List<Database.LeadConvertResult> results = convertLeads(this.qualifiedLeads);                
                publishConversionEvents(results);
                return;
            }
            
            List<Lead> leadsNotReady = new List<Lead>();
            for (Lead l : freshLeads) {
                if (l.RES_SLA_Status__c != 'Met') {
                    leadsNotReady.add(l);
                }
            }
            RES_LeadConversionRetryHandler.handleRetry(leadsNotReady, retryCount, freshLeads);
            
            } catch (Exception ex) {
                RES_LeadConversionRetryHandler.handleExceptionRetry(ex, retryCount, qualifiedLeads);
            }
    }
    
    private List<Database.LeadConvertResult> convertLeads(List<Lead> leadsToConvert) {
        Map<Id,List<SObject>> leadDuplicateMap = getDuplicateLeads(leadsToConvert, 'Account');
        if(leadDuplicateMap == null){
            leadDuplicateMap = new Map<Id,List<SObject>>();
        }
        
        Set<String> phoneNumbers = new Set<String>();
        for(Lead ld : leadsToConvert){
            phoneNumbers.add(ld.MobilePhone);
        }
        
        List<Contact> contactList = new RES_ContactDAOLayer().getContactByMobilePhone(phoneNumbers);
        Map<String,Id> phoneToContactMap = new Map<String,Id>();
        for(Contact c : contactList){
            phoneToContactMap.put(c.MobilePhone, c.Id);
        }
        
        List<Database.LeadConvert> leadsToConvertList = new List<Database.LeadConvert>();
        String convertedStatusLabel = new RES_LeadDAOLayer().getConvertedStatusLabel('Converted');
        
        for(Lead l : leadsToConvert){
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(l.Id);
            lc.setConvertedStatus(convertedStatusLabel);
            
            if(phoneToContactMap.containsKey(l.MobilePhone)){
                lc.setContactId(phoneToContactMap.get(l.MobilePhone));
            }
            
            if(leadDuplicateMap.containsKey(l.Id) && leadDuplicateMap.get(l.Id) != null && !leadDuplicateMap.get(l.Id).isEmpty()){
                Account acc = (Account)leadDuplicateMap.get(l.Id).get(0);
                lc.setAccountId(acc.Id);
            }
            
            lc.setOwnerId(l.OwnerId);
            leadsToConvertList.add(lc);
        }
    
        try{
            return Database.convertLead(leadsToConvertList, false, AccessLevel.USER_MODE);
        } catch(Exception ex){
            System.debug(LoggingLevel.ERROR, 'Conversion failed: ' + ex.getMessage());
            return new List<Database.LeadConvertResult>();
        }
    }
    
    private void publishConversionEvents(List<Database.LeadConvertResult> results) {
        List<RES_Lead_Conversion_Event__e> eventsToPublish = new List<RES_Lead_Conversion_Event__e>();
        
        for(Database.LeadConvertResult res : results){
            if(res.isSuccess()){        
                RES_Lead_Conversion_Event__e evt = new RES_Lead_Conversion_Event__e();
                evt.Lead_Id__c = String.valueOf(res.getLeadId());
                evt.Account_Id__c = String.valueOf(res.getAccountId());
                evt.Contact_Id__c = String.valueOf(res.getContactId());
                evt.Opportunity_Id__c = String.valueOf(res.getOpportunityId());
                evt.Converted_By__c = UserInfo.getUserId();
                eventsToPublish.add(evt);
            } else {
                for(Database.Error err : res.getErrors()){
                    System.debug(LoggingLevel.ERROR, 'Conversion error: ' + err.getMessage());
                }
            }
        }
        
        if(!eventsToPublish.isEmpty()){
            try {
                EventBus.publish(eventsToPublish);
            } catch(Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Event publish failed: ' + ex.getMessage());
            }
        }
    }
    
    private Map<Id,List<SObject>> getDuplicateLeads(List<Lead> inputLeads, String sObjectName) {
        Map<Id,List<SObject>> leadDuplicateMap = new Map<Id,List<SObject>>();
        if (inputLeads == null || inputLeads.isEmpty()) {
            return null;
        }  
        
        try {
            List<Datacloud.FindDuplicatesResult> results = Datacloud.FindDuplicates.findDuplicates(inputLeads); 
            for (Integer i = 0; i < results.size(); i++) {
                Datacloud.FindDuplicatesResult result = results[i];
                if (!result.isSuccess()) {
                    continue;
                }
    
                for (Datacloud.DuplicateResult dupResult : result.getDuplicateResults()) {
                    for (Datacloud.MatchResult matchResult : dupResult.getMatchResults()) {
                        if (!matchResult.isSuccess()) {
                            continue;
                        }
                        for (Datacloud.MatchRecord matchRecord : matchResult.getMatchRecords()) {
                            SObject record = matchRecord.getRecord();
                            if(sObjectName == 'Account' && record.getSObjectType() == Account.SObjectType) {
                                Account dupAccount = (Account) record;
                                if(!leadDuplicateMap.containsKey(inputLeads[i].Id)){
                                    leadDuplicateMap.put(inputLeads[i].Id, new List<SObject>());
                                }
                                leadDuplicateMap.get(inputLeads[i].Id).add(dupAccount);
                            }
                        }
                    }
                }
            }
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Duplicate check failed: ' + ex.getMessage());
        }
        
        return leadDuplicateMap;
    }

    private List<Lead> requeryleads(Set<Id> leadIds) {
        try {
            return new RES_LeadDAOLayer().getLeadsBySLAStatus(leadIds);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Requery failed: ' + ex.getMessage());
            return null;
        }
    }

    private Boolean checkAllLeadsReady(List<Lead> leads) {
        Integer notReadyCount = 0;
        for (Lead l : leads) {
            if (l.RES_SLA_Status__c != 'Met') {
                notReadyCount++;
            }
        }
        return notReadyCount == 0;
    }
}