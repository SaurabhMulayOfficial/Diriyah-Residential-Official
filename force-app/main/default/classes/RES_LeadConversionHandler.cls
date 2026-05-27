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
    public static void handleLeadConversion(List<Lead> leadsToConvert){
        Map<Id,List<SObject>> leadDuplicateMap =   getDuplicateLeads(leadsToConvert,'Account');
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
            Database.convertLead(qualifiedLeadsToConvert, true, AccessLevel.USER_MODE);
        }
        catch(Exception ex){
            System.debug('Exception while Converting Leads '+ex.getMessage());
        }
    }
    
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
}