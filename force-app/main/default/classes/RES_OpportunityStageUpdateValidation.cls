/**
* @ Class Name     	: RES_OpportunityStageUpdateValidation
* @ Description    	: This class is used to validate account details related to an opportunity before stage update.
* @ Author			: Nikhil Takawale
*/
public with sharing class RES_OpportunityStageUpdateValidation {
    
    @InvocableMethod(label = 'Opportunity Stage Update Validation')
    public static void validateOpportunity(List<Input> inputs) {
        
        if(!inputs.isEmpty()){
            
            Set<Id> accountIdSet = new Set<Id>();
            List<Opportunity> opportunityLstUpdate = new List<Opportunity>();
            Map<Id, Opportunity> opportunityUpdateMap = new Map<Id, Opportunity>();
            List<Contract> contractLstInsert = new List<Contract>();
            Id contractRecordTypeId = Schema.SObjectType.Contract
                .getRecordTypeInfosByDeveloperName()
                .get(System.Label.RES_Contract_Residential_Sales_RT)
                .getRecordTypeId();
            
            for(Input inputObj : inputs){
                if(inputObj.accountRecord != null){
                    Id recordTypeId = inputObj.accountRecord.RecordTypeId;
                    String recordType = Schema.SObjectType.Account
                        .getRecordTypeInfosById()
                        .get(recordTypeId)
                        .getDeveloperName();
                    
                    if((inputObj.accountRecord.BillingCountry != null && 
                        inputObj.accountRecord.BillingStreet != null &&
                        inputObj.accountRecord.BillingPostalCode != null &&
                        inputObj.accountRecord.BillingCity != null) && 
                       ((recordType == System.Label.RES_Company_RT && inputObj.accountRecord.RES_CR_number__c != null) || 
                        (recordType == System.Label.RES_Person_Account_RT && inputObj.accountRecord.RES_Identification_Number__c  != null))){
                            if(inputObj.opportunityRecord != null && checkOpportunityRecordTypeName(inputObj.opportunityRecord.RecordTypeId) && inputObj.quoteRecord.Status == 'Customer Approved' && checkQuoteRecordTypeName(inputObj.quoteRecord.RecordTypeId)){
                                Opportunity oppObj = new Opportunity(Id = inputObj.opportunityRecord.Id, StageName = 'Reservation');
                                if(!opportunityUpdateMap.containsKey(oppObj.Id)){
                                    opportunityUpdateMap.put(oppObj.Id, oppObj);
                                    opportunityLstUpdate.add(oppObj);
                                    
                                    Contract contractObj = new Contract();
                                    contractObj.AccountId = inputObj.accountRecord.Id;
                                    contractObj.Status = 'Draft';
                                    contractObj.RES_Opportunity_Id__c = oppObj.Id;
                                    contractObj.RecordTypeId = contractRecordTypeId;
                                    if(inputObj.quoteRecord.IsSyncing == true){
                                        contractObj.RES_Quote_Id__c = inputObj.quoteRecord.Id;
                                    }
                                    contractLstInsert.add(contractObj);
                                }
                            }
                            else{
                                accountIdSet.add(inputObj.accountRecord.Id);
                            }
                        }
                    else if(inputObj.opportunityRecord != null && checkOpportunityRecordTypeName(inputObj.opportunityRecord.RecordTypeId)){
                        Opportunity oppObj = new Opportunity(Id = inputObj.opportunityRecord.Id, StageName = 'Unit Selected');
                        if(!opportunityUpdateMap.containsKey(oppObj.Id)){
                            opportunityUpdateMap.put(oppObj.Id, oppObj);
                            opportunityLstUpdate.add(oppObj);
                        }
                    }
                }
            }
            
            if(!accountIdSet.isEmpty()){
                updateOpportunities(accountIdSet, contractRecordTypeId);
            }
            if(!opportunityLstUpdate.isEmpty()){
                Database.update(opportunityLstUpdate, false, AccessLevel.SYSTEM_MODE);
            }
            
            if(!contractLstInsert.isEmpty()){
                Database.insert(contractLstInsert, false, AccessLevel.SYSTEM_MODE);
                setContractOnQuotes(contractLstInsert);
            }
        }
    }
    
    private static void updateOpportunities(Set<Id> accountIdSet, Id contractRecordTypeId){
        
        List<Opportunity> opportunityLstUpdate = new List<Opportunity>();
        List<Opportunity> opportunityLst = new RES_OpportunityDAOLayer().getOpportunitiesRelatedToAccount(accountIdSet);
        List<Contract> contractLstInsert = new List<Contract>();
        
        if(opportunityLst != null){
            for(Opportunity opp : opportunityLst){
                Opportunity oppObj = new Opportunity(Id = opp.Id, StageName = 'Reservation');
                opportunityLstUpdate.add(oppObj);
                
                Contract contractObj = new Contract();
                contractObj.AccountId = opp.AccountId;
                contractObj.Status = 'Draft';
                contractObj.RES_Opportunity_Id__c = oppObj.Id;
                contractObj.RecordTypeId = contractRecordTypeId;
                if(!opp.Quotes.isEmpty()){
                    contractObj.RES_Quote_Id__c = opp.Quotes[0].Id;
                }
                contractLstInsert.add(contractObj);
            }
            if(!opportunityLstUpdate.isEmpty()){
                Database.update(opportunityLstUpdate, false, AccessLevel.SYSTEM_MODE);
            }
            if(!contractLstInsert.isEmpty()){
                Database.insert(contractLstInsert, false, AccessLevel.SYSTEM_MODE);
                setContractOnQuotes(contractLstInsert);
            }
        }
    }
    
    private static Boolean checkOpportunityRecordTypeName(Id opportunityRecordTypeId){
        String recordType = Schema.SObjectType.Opportunity
            .getRecordTypeInfosById()
            .get(opportunityRecordTypeId)
            .getDeveloperName();
        if(recordType == System.Label.RES_Opportunity_Single_Buyer_RT || recordType == System.Label.RES_Opportunity_Multi_Buyer_RT){
            return true;
        }
        return false;
    }
    
    private static Boolean checkQuoteRecordTypeName(Id quoteRecordTypeId){
        String recordType = Schema.SObjectType.Quote
            .getRecordTypeInfosById()
            .get(quoteRecordTypeId)
            .getDeveloperName();
        if(recordType == System.Label.RES_Quote_Residential_Sales_RT){
            return true;
        }
        return false;
    }
    
    private static void setContractOnQuotes(List<Contract> contractLst){
        Map<Id, Id> quoteMap = new Map<Id, Id>();
        List<Quote> quoteLstUpdate = new List<Quote>();
        for(Contract contractObj : contractLst){
            if(contractObj.RES_Quote_Id__c != null){
                Quote quoteObj = new Quote(Id = contractObj.RES_Quote_Id__c, ContractId = contractObj.Id);
                if(!quoteMap.containsKey(quoteObj.Id)){
                    quoteMap.put(quoteObj.Id, quoteObj.Id);
                    quoteLstUpdate.add(quoteObj);
                }
            }
        }
        if(!quoteLstUpdate.isEmpty()){
            Database.update(quoteLstUpdate, false, AccessLevel.SYSTEM_MODE);
        }
    }
    
    public class Input {
        @InvocableVariable public Account accountRecord;
        @InvocableVariable public Opportunity opportunityRecord;
        @InvocableVariable public Quote quoteRecord;
    }
}