/**
* @ Class Name     	: RES_OpportunityStageUpdateValidation
* @ Description    	: This class is used to validate account details related to an opportunity before stage update.
* @ Author			: Nikhil Takawale
*/
public with sharing class RES_OpportunityStageUpdateValidation {
    
    @InvocableMethod(label = 'Opportunity Stage Update Validation')
    public static void validateOpportunity(List<Input> inputs) {
        
        if(!inputs.isEmpty()){

            List<Opportunity> opportunityLstUpdate = new List<Opportunity>();
            Id recordTypeId = inputs[0].accountRecord.RecordTypeId;
            String recordType = Schema.SObjectType.Account
                                .getRecordTypeInfosById()
                                .get(recordTypeId)
                                .getDeveloperName();
            
            if((inputs[0].accountRecord.BillingCountry != null && 
                inputs[0].accountRecord.BillingStreet != null &&
                inputs[0].accountRecord.BillingPostalCode != null &&
                inputs[0].accountRecord.BillingCity != null) && 
               ((recordType == System.Label.RES_Company_RT && inputs[0].accountRecord.RES_CR_number__c != null) || 
                (recordType == System.Label.RES_Person_Account_RT && inputs[0].accountRecord.RES_Identification_Number__c  != null))){
                    if(inputs[0].opportunityRecordId != null){
                        Opportunity oppObj = new Opportunity(Id = inputs[0].opportunityRecordId, StageName = 'Unit Selected');
                        opportunityLstUpdate.add(oppObj);
                    }
                    else{
                        updateOpportunities(inputs[0].accountRecord.Id);
                    }
                }

            if(!opportunityLstUpdate.isEmpty()){
                Database.update(opportunityLstUpdate, false, AccessLevel.SYSTEM_MODE);
            }
        }
    }
    
    private static void updateOpportunities(Id accountId){
        List<Opportunity> opportunityLstUpdate = new List<Opportunity>();
        List<Opportunity> opportunityLst = new RES_OpportunityDAOLayer().getOpportunitiesRelatedToAccount(accountId);
        
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