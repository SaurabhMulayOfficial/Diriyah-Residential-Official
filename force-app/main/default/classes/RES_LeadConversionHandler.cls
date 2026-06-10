/**
 * ==============================================================================
 * Class Name    : RES_LeadConversionHandler
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
 * Version       : 1.0
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
        convertLeads(leadsToConvert, leadDuplicateMap, phoneToContactMap);
    }
    /**
 * @description Converts Lead records in bulk by dynamically associating
 *              existing Contacts and duplicate Accounts during conversion.
 *              Uses Database.convertLead() in USER_MODE access context.
 *
 * @param leadsToConvert List of Leads to convert.
 * @param leadDuplicateMap Map containing duplicate Account/Lead
 *                         records against each Lead.
 * @param phoneToContactMap Map of Mobile Phone to existing Contact Id.
 */
    public static void convertLeads(List<Lead> leadsToConvert, Map<Id,List<SObject>> leadDuplicateMap, Map<String,Id> phoneToContactMap){
        List<Database.LeadConvert> qualifiedLeadsToConvert = new List<Database.LeadConvert>();
        String convertedStatusLabel = new RES_LeadDAOLayer().getConvertedStatusLabel('Qualified');
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
            List<Database.LeadConvertResult> results = Database.convertLead(qualifiedLeadsToConvert,true, AccessLevel.USER_MODE);
                for(Database.LeadConvertResult res : results){
                    if(!res.isSuccess()){
                        for(Database.Error err : res.getErrors()){
                            System.debug(err.getMessage());
                        }
                    }
                }
        }
        catch(Exception ex){
            System.debug('Exception while Converting Leads '+ex.getMessage());
        }
    }
/**
 * @description Identifies duplicate Lead or Account records using
 *              Datacloud.FindDuplicates APIs and returns matching records
 *              mapped against input Lead Ids.
 *
 * @param inputLeads List of Lead records for duplicate checking.
 * @param sObjectName Target duplicate object type
 *                    ('Lead' or 'Account').
 *
 * @return Map<Id,List<SObject>> Map of Lead Id to duplicate records.
 */
    public static Map<Id,List<SObject>> getDuplicateLeads(List<Lead> inputLeads, String sObjectName) {
        Map<Id,List<SObject>> leadDuplicateMap = new Map<Id,List<Lead>>();
        if (inputLeads == null || inputLeads.isEmpty()) {
            return null;
        }
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
        return leadDuplicateMap;
    }

    /**
     * @description Fetches converted record Ids after Lead conversion.
     *              Delegates SOQL to RES_LeadDAOLayer following DAO framework.
     *              Called from LWC after CDC LeadChangeEvent is received.
     *
     * @param leadId Id of the converted Lead.
     * @return Map containing accountId, contactId, opportunityId, leadName, status.
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
                result.put('accountType',      acc.Type);
                result.put('accountPhone',     acc.Phone);
                result.put('accountWebsite',   acc.Website);
                result.put('accountOwnerName', acc.Owner?.Name);
                result.put('accountSite',      acc.Site);
                result.put('isPersonAccount',  String.valueOf(acc.IsPersonAccount));
            }
        }

        if (convertedLead.ConvertedContactId != null) {
            Contact con = new RES_ContactDAOLayer().getContactById(
                convertedLead.ConvertedContactId
            );
            if (con != null) {
                result.put('contactName',   con.Name);
                result.put('contactTitle',  con.Title);
                result.put('contactPhone',  con.Phone);
                result.put('contactEmail',  con.Email);
                result.put('contactMobile', con.MobilePhone);
            }
        }

        if (convertedLead.ConvertedOpportunityId != null) {
            Opportunity opp = new RES_OpportunityDAOLayer().getOpportunityById(
                convertedLead.ConvertedOpportunityId
            );
            if (opp != null) {
                result.put('opportunityName',      opp.Name);
                result.put('opportunityCloseDate', opp.CloseDate != null ? opp.CloseDate.format() : '');
                result.put('opportunityAmount',    opp.Amount != null ? String.valueOf(opp.Amount) : '');
                result.put('opportunityOwnerName', opp.Owner?.Name);
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