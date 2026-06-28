/**
 * ==============================================================================
 * Class Name    : RES_LeadConversionHandler (REFACTORED)
 * Description   : Utility class responsible for automated Lead conversion with
 *                 duplicate handling and Contact association logic.
 *                 
 *                 This class:
 *                 • Identifies duplicate Leads or Accounts using
 *                   Datacloud duplicate matching APIs.
 *                 • Maps existing Contacts based on Mobile Phone.
 *                 • Dynamically associates existing Contacts and Accounts
 *                   during Lead conversion.
 *                 • Performs bulk Lead conversion using
 *                   Database.convertLead().
 *                 • Supports duplicate validation for both Lead and Account
 *                   records through Datacloud.FindDuplicates APIs.
 *
 * Methods       :
 *                 • handleLeadConversion()
 *                 • convertLeads()
 *                 • getDuplicateLeads()
 *
 * Author        : Roshan Jambhule
 * Company       : Globant Inc
 * Created Date  : May 27, 2026
 * Version       : 2.0 (REFACTORED - No Duplication)
 * ==============================================================================
 */
public with sharing class RES_LeadConversionHandler {

    /**
     * @description Entry method responsible for processing bulk Lead conversion.
     *              Fetches duplicate Account mappings and existing Contact mappings
     *              based on Mobile Phone, then initiates Lead conversion.
     *
     * @param leadsToConvert List of Lead records to be converted.
     */
    public static void handleLeadConversion(List<Lead> leadsToConvert){
        Map<Id,List<SObject>> leadDuplicateMap = getDuplicateLeads(leadsToConvert,'Account');
        if(leadDuplicateMap == null){
            return;
        }
        Set<String> phoneNumber = new Set<String>();
        for(Lead ld:leadsToConvert){
            phoneNumber.add(ld.MobilePhone);
        }
        List<Contact> contactList = new RES_ContactDAOLayer().getContactByMobilePhone(phoneNumber);
        Map<String,Id> phoneToContactMap = new Map<String,Id>();
        for(Contact c : contactList){
            phoneToContactMap.put(c.MobilePhone, c.Id);
        }
        convertLeadsAndReturnResults(leadsToConvert, leadDuplicateMap, phoneToContactMap);
    }

    /**
     * @description SINGLE SOURCE OF TRUTH - Converts leads and optionally returns results
     *              This eliminates code duplication between convertLeads() and 
     *              convertLeadsAndReturnResults()
     *
     * @param leadsToConvert List of Lead records to be converted
     * @param leadDuplicateMap Map containing duplicate Account/Lead records
     * @param phoneToContactMap Map of Mobile Phone to existing Contact Id
     * @return List<Database.LeadConvertResult> Conversion results with IDs
     */
    public static List<Database.LeadConvertResult> convertLeadsAndReturnResults(
        List<Lead> leadsToConvert, 
        Map<Id,List<SObject>> leadDuplicateMap, 
        Map<String,Id> phoneToContactMap){
        
        List<Database.LeadConvert> qualifiedLeadsToConvert = new List<Database.LeadConvert>();
        String convertedStatusLabel = new RES_LeadDAOLayer().getConvertedStatusLabel('Converted');
        for(Lead l:leadsToConvert){
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
            qualifiedLeadsToConvert.add(lc);
        }

        try{
            List<Database.LeadConvertResult> results = Database.convertLead(qualifiedLeadsToConvert, false, AccessLevel.USER_MODE);
            for(Database.LeadConvertResult res : results){
                if(res.isSuccess()){
                    publishLeadConversionEvent(res);
                } else {
                    for(Database.Error err : res.getErrors()){
                        System.debug(LoggingLevel.ERROR, 'Lead Conversion Error: ' + err.getMessage());
                    }
                }
            }
            
            return results;
        }
        catch(Exception ex){
            System.debug(LoggingLevel.ERROR, 'Exception while Converting Leads: ' + ex.getMessage());
            return new List<Database.LeadConvertResult>();
        }
    }

    /**
     * @description WRAPPER - For backward compatibility with existing code
     *              that calls convertLeads() without expecting return value.
     *              Internally calls convertLeadsAndReturnResults()
     *
     * @param leadsToConvert List of Leads to convert
     * @param leadDuplicateMap Map containing duplicate Account/Lead records
     * @param phoneToContactMap Map of Mobile Phone to existing Contact Id
     */
    public static void convertLeads(
        List<Lead> leadsToConvert, 
        Map<Id,List<SObject>> leadDuplicateMap, 
        Map<String,Id> phoneToContactMap){
        convertLeadsAndReturnResults(leadsToConvert, leadDuplicateMap, phoneToContactMap);
    }

    /**
     * @description Identifies duplicate Lead or Account records using
     *              Datacloud.FindDuplicates APIs and returns matching records
     *              mapped against input Lead Ids.
     *
     * @param inputLeads List of Lead records for duplicate checking
     * @param sObjectName Target duplicate object type ('Lead' or 'Account')
     * @return Map<Id,List<SObject>> Map of Lead Id to duplicate records
     */
    public static Map<Id,List<SObject>> getDuplicateLeads(List<Lead> inputLeads, String sObjectName) {
        Map<Id,List<SObject>> leadDuplicateMap = new Map<Id,List<SObject>>();
        if (inputLeads == null || inputLeads.isEmpty()) {
            return null;
        }
        
        try {
            List<Datacloud.FindDuplicatesResult> results = Datacloud.FindDuplicates.findDuplicates(inputLeads);
            for (Integer i = 0; i < results.size(); i++) {
                Datacloud.FindDuplicatesResult result = results[i];
                if (!result.isSuccess()) {
                    for (Database.Error err : result.getErrors()) {
                        inputLeads[i].addError(err.getMessage());
                    }
                    continue;
                }

                for (Datacloud.DuplicateResult dupResult : result.getDuplicateResults()) {
                    for (Datacloud.MatchResult matchResult : dupResult.getMatchResults()) {
                        if (!matchResult.isSuccess()) {
                            continue;
                        }
                        
                        for (Datacloud.MatchRecord matchRecord : matchResult.getMatchRecords()) {
                            SObject record = matchRecord.getRecord();
                            
                            if(sObjectName == 'Lead' && record.getSObjectType() == Lead.SObjectType) {
                                Lead dupLead = (Lead) record;
                                if(!leadDuplicateMap.containsKey(inputLeads[i].Id)){
                                    leadDuplicateMap.put(inputLeads[i].Id, new List<SObject>());
                                }
                                leadDuplicateMap.get(inputLeads[i].Id).add(dupLead);
                            }
                            
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
            System.debug(LoggingLevel.ERROR, 'Duplicate detection failed: ' + ex.getMessage());
        }
        
        return leadDuplicateMap;
    }

    /**
     * @description Publishes Lead Conversion Platform Event with converted record IDs
     *
     * @param res Database.LeadConvertResult containing conversion details
     */
    private static void publishLeadConversionEvent(Database.LeadConvertResult res){
        if(res == null){
            return;
        }
    
        RES_Lead_Conversion_Event__e evt = new RES_Lead_Conversion_Event__e();
        evt.Lead_Id__c        = String.valueOf(res.getLeadId());
        evt.Account_Id__c     = String.valueOf(res.getAccountId());
        evt.Contact_Id__c     = String.valueOf(res.getContactId());
        evt.Opportunity_Id__c = String.valueOf(res.getOpportunityId());
        evt.Converted_By__c   = UserInfo.getUserId();
    
        Database.SaveResult publishResult = EventBus.publish(evt);
        if(!publishResult.isSuccess()){
            for(Database.Error err : publishResult.getErrors()){
                System.debug(LoggingLevel.ERROR,'Platform Event Publish Failed: ' + err.getMessage());
            }
        }
    }

    /**
     * @description Fetches converted record Ids after Lead conversion.
     *              Delegates SOQL to RES_LeadDAOLayer following DAO framework.
     *              Called from LWC after CDC LeadChangeEvent is received.
     *
     * @param leadId Id of the converted Lead
     * @return Map containing accountId, contactId, opportunityId, leadName, status
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, String> getConvertedRecordIds(Id leadId) {
        Map<String, String> result = new Map<String, String>();
        try {
            if (leadId == null) {
                throw new AuraHandledException('Lead Id is required.');
            }
            
            Lead convertedLead = new RES_LeadDAOLayer().getConvertedLeadById(leadId);
            if (convertedLead == null) {
                return result; // LWC retry handles this
            }

            result.put('accountId',     convertedLead.ConvertedAccountId);
            result.put('contactId',     convertedLead.ConvertedContactId);
            result.put('opportunityId', convertedLead.ConvertedOpportunityId);
            result.put('leadName',      convertedLead.Name);
            result.put('status',        convertedLead.Status);
            result.put('LastModifiedById', convertedLead.LastModifiedById);

            if (convertedLead.ConvertedAccountId != null) {
                Account acc = new RES_AccountDAOLayer().getAccountById(
                    convertedLead.ConvertedAccountId
                );
                if (acc != null) {
                    result.put('accountName',      acc.Name);
                    result.put('accountPhone',     acc.Phone);
                    result.put('accountWebsite',   acc.Website);
                    result.put('accountOwnerName', acc.Owner?.Name);
                    result.put('isPersonAccount',  String.valueOf(acc.IsPersonAccount));
                    result.put('accountSource',    acc.AccountSource);
                    result.put('accountRating',    acc.Rating);
                    result.put('accountMobile',    acc.PersonMobilePhone);
                    result.put('accountEmail',     acc.PersonEmail);
                }
            }

            if (convertedLead.ConvertedContactId != null) {
                Contact con = new RES_ContactDAOLayer().getContactById(
                    convertedLead.ConvertedContactId
                );
                if (con != null) {
                    result.put('contactName',       con.Name);
                    result.put('contactEmail',      con.Email);
                    result.put('contactMobile',     con.MobilePhone);
                    result.put('contactLeadSource', con.LeadSource);
                }
            }

            if (convertedLead.ConvertedOpportunityId != null) {
                Opportunity opp = new RES_OpportunityDAOLayer().getOpportunityById(
                    convertedLead.ConvertedOpportunityId
                );
                if (opp != null) {
                    result.put('opportunityName',      opp.Name);
                    result.put('opportunityCloseDate', opp.CloseDate != null ? opp.CloseDate.format() : '');
                    result.put('opportunityOwnerName', opp.Owner?.Name);
                    result.put('opportunityProject',   opp.RES_Project__c);
                    
                    String leadSourceLabel = '';
                    if(opp.LeadSource != null){
                        Schema.DescribeFieldResult dfr = Opportunity.LeadSource.getDescribe();
                        for(Schema.PicklistEntry pe : dfr.getPicklistValues()){
                            if(pe.getValue() == opp.LeadSource){
                                leadSourceLabel = pe.getLabel();
                                break;
                            }
                        }
                    }
                    result.put('opportunityLeadSource', leadSourceLabel);
                }
            }
            
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            System.debug('Error: ' + ex.getMessage() + ' | Line: ' + ex.getLineNumber());
            throw new AuraHandledException('Error: ' + ex.getMessage());
        }
        
        return result;
    }
}