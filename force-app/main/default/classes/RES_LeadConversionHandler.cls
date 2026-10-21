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
        Map<Id, ConversionTarget> targets = resolveConversionTargets(leadsToConvert, leadDuplicateMap, phoneToContactMap);
        for(Lead l:leadsToConvert){
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(l.Id);
            lc.setConvertedStatus(convertedStatusLabel);

            ConversionTarget target = targets.get(l.Id);
            if(target.contactId != null){
                lc.setContactId(target.contactId);
            }
            if(target.accountId != null){
                lc.setAccountId(target.accountId);
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
     * @description Existing Account / Contact that a Lead should be converted into.
     */
    public class ConversionTarget {
        public Id accountId;
        public Id contactId;
    }

    /**
     * @description Decides which existing Account / Contact (if any) each Lead is converted into.
     *              A match is only honoured when the matched record is of the same type as the Lead:
     *              • Company Lead    -> Business Account / Business Account's Contact
     *              • Individual Lead -> Person Account / Person Account's Contact
     *              A cross-type match (e.g. Company Lead whose mobile equals a Person Account's mobile)
     *              is ignored so that new records are created instead of failing the conversion.
     *              A matched Contact that belongs to a different Account than the matched Account is
     *              also ignored, as Salesforce rejects that combination. When only a Contact matches,
     *              its Account is used as the target (Salesforce requires accountId with contactId).
     *              Leads with an unknown record type keep the previous (unfiltered) behaviour.
     *
     * @param leads             Leads being converted
     * @param leadDuplicateMap  Lead Id -> duplicate Accounts found through Datacloud matching
     * @param phoneToContactMap Mobile Phone -> existing Contact Id
     * @return Map<Id,ConversionTarget> Lead Id -> Account / Contact to use (values may be null)
     */
    public static Map<Id, ConversionTarget> resolveConversionTargets(
        List<Lead> leads,
        Map<Id,List<SObject>> leadDuplicateMap,
        Map<String,Id> phoneToContactMap){

        Map<Id, ConversionTarget> targets = new Map<Id, ConversionTarget>();
        Map<Id, Id> leadToAccountId = new Map<Id, Id>();
        Map<Id, Id> leadToContactId = new Map<Id, Id>();

        for(Lead l : leads){
            targets.put(l.Id, new ConversionTarget());
            if(leadDuplicateMap != null && leadDuplicateMap.containsKey(l.Id)
               && leadDuplicateMap.get(l.Id) != null && !leadDuplicateMap.get(l.Id).isEmpty()){
                leadToAccountId.put(l.Id, ((Account) leadDuplicateMap.get(l.Id).get(0)).Id);
            }
            if(phoneToContactMap != null && l.MobilePhone != null && phoneToContactMap.containsKey(l.MobilePhone)){
                leadToContactId.put(l.Id, phoneToContactMap.get(l.MobilePhone));
            }
        }

        Map<Id, Account> accountMap = new RES_AccountDAOLayer().getAccountTypesByIds(new Set<Id>(leadToAccountId.values()));
        Map<Id, Contact> contactMap = new RES_ContactDAOLayer().getContactsWithAccountTypeByIds(new Set<Id>(leadToContactId.values()));

        Map<String, List<Contact>> contactsByMobile = new Map<String, List<Contact>>();
        for(Lead l : leads){
            Boolean isIndividual = isIndividualLead(l);
            Id accountId = leadToAccountId.get(l.Id);
            Id contactId = leadToContactId.get(l.Id);

            if(accountId != null && isIndividual != null){
                Account matchedAccount = accountMap.get(accountId);
                if(matchedAccount == null || (matchedAccount.IsPersonAccount == true) != isIndividual){
                    accountId = null;
                }
            }

            if(contactId != null){
                Contact chosen = contactMap.get(contactId);
                if(!isContactUsable(chosen, isIndividual, accountId)){
                    // The mobile can be shared by contacts of both types - look for one of the right type
                    chosen = null;
                    for(Contact c : getContactsByMobile(l.MobilePhone, contactsByMobile)){
                        if(isContactUsable(c, isIndividual, accountId)){
                            chosen = c;
                            break;
                        }
                    }
                }
                contactId = chosen != null ? chosen.Id : null;
                // Salesforce requires an accountId whenever a contactId is passed
                if(chosen != null && accountId == null){
                    accountId = chosen.AccountId;
                }
            }

            targets.get(l.Id).accountId = accountId;
            targets.get(l.Id).contactId = contactId;
        }
        return targets;
    }

    private static Boolean isContactUsable(Contact c, Boolean isIndividual, Id accountId){
        if(c == null){
            return false;
        }
        if(isIndividual != null && (c.Account.IsPersonAccount == true) != isIndividual){
            return false;
        }
        return accountId == null || c.AccountId == accountId;
    }

    // Contacts sharing the Lead's mobile; queried lazily, only when the first match was not usable
    private static List<Contact> getContactsByMobile(String mobile, Map<String, List<Contact>> cache){
        if(String.isBlank(mobile)){
            return new List<Contact>();
        }
        if(!cache.containsKey(mobile)){
            List<Contact> found = new RES_ContactDAOLayer().getContactByMobilePhone(new Set<String>{ mobile });
            cache.put(mobile, found != null ? found : new List<Contact>());
        }
        return cache.get(mobile);
    }

    /**
     * @description true = Individual Lead, false = Company Lead, null = unknown record type.
     */
    private static Boolean isIndividualLead(Lead l){
        if(l.RecordTypeId == null){
            return null;
        }
        Schema.RecordTypeInfo info = Schema.SObjectType.Lead.getRecordTypeInfosById().get(l.RecordTypeId);
        if(info == null){
            return null;
        }
        if(info.getDeveloperName() == 'RES_Individual'){
            return true;
        }
        if(info.getDeveloperName() == 'RES_Company'){
            return false;
        }
        return null;
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

    @AuraEnabled(cacheable=false)
    public static Boolean getPendingQualifiedFlag(Id leadId) {
        if (leadId == null) return false;
        Lead lead = new RES_LeadDAOLayer().getLeadPendingQualifiedFlag(leadId);
        return lead != null && lead.RES_Pending_Qualified_Review__c;
    }

    @AuraEnabled(cacheable=false)
    public static void triggerLeadConversion(Id leadId) {
        try {
            if (leadId == null) {
                throw new AuraHandledException('Lead Id is required.');
            }
            List<Lead> leads = new RES_LeadDAOLayer().getLeadsBySLAStatus(new Set<Id>{ leadId });
            if (leads == null || leads.isEmpty()) {
                throw new AuraHandledException('Lead not found.');
            }
            System.enqueueJob(new RES_LeadConversionQueueable(leads));
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            System.debug('triggerLeadConversion error: ' + ex.getMessage());
            throw new AuraHandledException('Error: ' + ex.getMessage());
        }
    }
}