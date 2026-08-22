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
            List<Quote> quoteLstUpdate = new List<Quote>();
            Map<Id, Opportunity> opportunityUpdateMap = new Map<Id, Opportunity>();
            List<Map<String, Object>> inputsMap = new List<Map<String, Object>>();
            
            for(Input inputObj : inputs){
                if(inputObj.accountRecord != null){
                    if(inputObj.opportunityRecord != null){
                        if(inputObj.opportunityRecord.StageName == 'Proposal' && checkOpportunityRecordTypeName(inputObj.opportunityRecord.RecordTypeId)){
                            Opportunity oppObj = new Opportunity(Id = inputObj.opportunityRecord.Id, StageName = 'Unit Selected');
                            if(!opportunityUpdateMap.containsKey(oppObj.Id)){
                                opportunityUpdateMap.put(oppObj.Id, oppObj);
                                opportunityLstUpdate.add(oppObj);
                            }
                        }
                        if(inputObj.opportunityRecord.StageName == 'Unit Selected' && checkOpportunityRecordTypeName(inputObj.opportunityRecord.RecordTypeId)){
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
                                    if(inputObj.quoteRecord != null){
                                        if(inputObj.quoteRecord.Status == 'Customer Approved' && inputObj.quoteRecord.IsSyncing == true && checkQuoteRecordTypeName(inputObj.quoteRecord.RecordTypeId)){
                                            Opportunity oppObj = new Opportunity(Id = inputObj.opportunityRecord.Id, StageName = 'Reservation');
                                            if(!opportunityUpdateMap.containsKey(oppObj.Id)){
                                                Id contractRecordTypeId = Schema.SObjectType.Contract
                                                    .getRecordTypeInfosByDeveloperName()
                                                    .get(System.Label.RES_Contract_Residential_Sales_RT)
                                                    .getRecordTypeId();
                                                
                                                opportunityUpdateMap.put(oppObj.Id, oppObj);
                                                opportunityLstUpdate.add(oppObj);
                                                
                                                inputsMap.add(new Map<String, Object>{
                                                    'sourceId' => (String) inputObj.quoteRecord.Id,
                                                    'contractPriceOption' => 'NET_UNIT_PRICE_ONLY'
                                                });
                                                
                                                Quote quoteObj = new Quote(Id = inputObj.quoteRecord.Id, RES_Reservation_Start_Date__c = SYSTEM.NOW());
                                                quoteLstUpdate.add(quoteObj);
                                            }
                                        }
                                    }
                                }
                        }
                    }
                    else{
                        accountIdSet.add(inputObj.accountRecord.Id);
                    }
                }
            }
            if(!accountIdSet.isEmpty()){
                updateOpportunities(accountIdSet);
            }
            if(!opportunityLstUpdate.isEmpty()){
                Database.update(opportunityLstUpdate, false, AccessLevel.SYSTEM_MODE);
            }
            if(inputsMap.size() > 0){
                createContractOnQuotes(inputsMap);
            }
            if(!quoteLstUpdate.isEmpty()){
                Database.update(quoteLstUpdate, false, AccessLevel.SYSTEM_MODE);
            }
        }
    }
    
    private static void updateOpportunities(Set<Id> accountIdSet){
        List<Quote> quoteLstUpdate = new List<Quote>();
        List<Opportunity> opportunityLstUpdate = new List<Opportunity>();
        List<Opportunity> opportunityLst = new RES_OpportunityDAOLayer().getOpportunitiesRelatedToAccount(accountIdSet);
        Id contractRecordTypeId = Schema.SObjectType.Contract
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Contract_Residential_Sales_RT)
            .getRecordTypeId();
        List<Map<String, Object>> inputsMap = new List<Map<String, Object>>();
        
        if(opportunityLst != null){
            for(Opportunity opp : opportunityLst){
                if(!opp.Quotes.isEmpty()){
                    Opportunity oppObj = new Opportunity(Id = opp.Id, StageName = 'Reservation');
                    opportunityLstUpdate.add(oppObj);
                    
                    inputsMap.add(new Map<String, Object>{
                        'sourceId' => (String) opp.Quotes[0].Id,
                        'contractPriceOption' => 'NET_UNIT_PRICE_ONLY'
                    });
                    
                    Quote quoteObj = new Quote(Id = opp.Quotes[0].Id, RES_Reservation_Start_Date__c = SYSTEM.NOW());
                    quoteLstUpdate.add(quoteObj);
                }
            }
            if(!opportunityLstUpdate.isEmpty()){
                Database.update(opportunityLstUpdate, false, AccessLevel.SYSTEM_MODE);
            }
            if(inputsMap.size() > 0){
                createContractOnQuotes(inputsMap);
            }
            if(!quoteLstUpdate.isEmpty()){
                Database.update(quoteLstUpdate, false, AccessLevel.SYSTEM_MODE);
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
    
    private static void createContractOnQuotes(List<Map<String, Object>> inputsMap){
        Invocable.Action action = Invocable.Action.createStandardAction('createContract');
        Set<Id> contractIdSet = new Set<Id>();
        action.setInvocations(inputsMap);
        List<Invocable.Action.Result> results = action.invoke();
        for(Invocable.Action.Result resultObj : results) {
            if(resultObj.isSuccess()) {
                Map<String, Object> outputs = resultObj.getOutputParameters();
                Id contractId = (Id) outputs.get('contractId');
                contractIdSet.add(contractId);
            }
        }
        if(!contractIdSet.isEmpty()){
            List<Quote> quotesLst = new RES_QuoteDAOLayer().getQuotesByContractIds(contractIdSet, 'Customer Approved');
            List<Contract> contractLstUpdate = new List<Contract>();
            if(!quotesLst.isEmpty()){
                for(Quote quoteObj : quotesLst){
                    Contract contractObj = new Contract(Id = quoteObj.ContractId, SourceQuoteId = quoteObj.Id, SourceOpportunityId = quoteObj.OpportunityId);
                    contractLstUpdate.add(contractObj);
                }
            }
            if(!contractLstUpdate.isEmpty()){
                Database.update(contractLstUpdate, false, AccessLevel.SYSTEM_MODE);
            }
        }
    }
    
    public class Input {
        @InvocableVariable public Account accountRecord;
        @InvocableVariable public Opportunity opportunityRecord;
        @InvocableVariable public Quote quoteRecord;
    }
}