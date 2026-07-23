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
            for(Input inputObj : inputs){
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
                        if(inputObj.opportunityRecordId != null){
                            Opportunity oppObj = new Opportunity(Id = inputObj.opportunityRecordId, StageName = 'Unit Selected');
                            opportunityLstUpdate.add(oppObj);
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
        }
    }
    
    private static void updateOpportunities(Set<Id> accountIdSet){
        List<Opportunity> opportunityLstUpdate = new List<Opportunity>();
        List<Opportunity> opportunityLst = new RES_OpportunityDAOLayer().getOpportunitiesRelatedToAccount(accountIdSet);
        
        if(opportunityLst != null){
            for(Opportunity opp : opportunityLst){
                Opportunity oppObj = new Opportunity(Id = opp.Id, StageName = 'Unit Selected');
                opportunityLstUpdate.add(oppObj);
            }
            if(!opportunityLstUpdate.isEmpty()){
                Database.update(opportunityLstUpdate, false, AccessLevel.SYSTEM_MODE);
            }
        }
    }
    
    public class Input {
        @InvocableVariable public Account accountRecord;
        @InvocableVariable public Id opportunityRecordId;
    }
}