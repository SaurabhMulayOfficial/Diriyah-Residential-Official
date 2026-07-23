@isTest
public class RES_OpportunityStageUpdateValidationTest {
	@testSetup
    public static void setupTestData(){
        Test.startTest();
        Account companyAccount = RES_TestDataFactory.createCompanyRTAccount('Globant');
        Opportunity singleOpportunity = RES_TestDataFactory.createSingleBuyerOpportunity('Globant', companyAccount.Id, 'Proposal', Date.Today(), 'Amansamar Residences Wadi Safar');
    	Quote quoteObj = RES_TestDataFactory.createQuote('Test Quote', singleOpportunity.Id, Test.getStandardPricebookId(), 'Draft');
    	QuoteLineItem qli = RES_TestDataFactory.createQuoteLineItem(quoteObj.Id, 2, 100);
    	Account updateAccount = new Account(Id = companyAccount.Id, RES_CR_number__c = '1234567890', RES_Identification_Type__c = 'ZIT04');
        update updateAccount;
        Test.stopTest();
    }
    
    @isTest
    public static void validateOpportunityTest(){
        Test.startTest();
        List<RES_OpportunityStageUpdateValidation.Input> inputs = new List<RES_OpportunityStageUpdateValidation.Input>();
        List<Account> accountLst = [ SELECT Id, RecordTypeId, BillingCountry, BillingStreet, BillingPostalCode, BillingCity, RES_CR_number__c, RES_Identification_Number__c
                                     FROM Account 
                                     WHERE Name = 'Globant' ];
        if(!accountLst.isEmpty()){
            RES_OpportunityStageUpdateValidation.Input input = new RES_OpportunityStageUpdateValidation.Input();
            input.accountRecord = accountLst[0];
            inputs.add(input);
            RES_OpportunityStageUpdateValidation.validateOpportunity(inputs);
            List<Opportunity> oppLst = [ SELECT StageName
                                         FROM Opportunity 
                                         WHERE Name = 'Globant' AND 
                                         AccountId =: accountLst[0].Id ];
            if(!oppLst.isEmpty()){
                Assert.areEqual('Unit Selected', oppLst[0].StageName);
            }
        }
        Test.stopTest();
    }
}