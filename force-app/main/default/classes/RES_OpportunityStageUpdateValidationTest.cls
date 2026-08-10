@isTest
public class RES_OpportunityStageUpdateValidationTest {
	@testSetup
    public static void setupTestData(){
        Test.startTest();
        Account companyAccount = RES_TestDataFactory.createCompanyRTAccount('Globant', '1212121212');
        Opportunity singleOpportunity = RES_TestDataFactory.createSingleBuyerOpportunity('Globant', companyAccount.Id, 'Proposal', Date.Today(), 'Amansamar Residences Wadi Safar');
        Id quoteRecordTypeId = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Quote_Residential_Sales_RT)
            .getRecordTypeId();
        Quote quoteObj = RES_TestDataFactory.createQuote('Test Quote', singleOpportunity.Id, Test.getStandardPricebookId(), 'Customer Approved', quoteRecordTypeId);
        singleOpportunity.SyncedQuoteId = quoteObj.Id;
        update singleOpportunity;
        
        Account diriyahAccount = RES_TestDataFactory.createCompanyRTAccount('Diriyah', '3434343434');
        Opportunity diriyahOpportunity = RES_TestDataFactory.createSingleBuyerOpportunity('Diriyah', diriyahAccount.Id, 'Unit Selected', Date.Today().addDays(30), 'Amansamar Residences Wadi Safar');
        diriyahOpportunity.Pricebook2Id = Test.getStandardPricebookId();
        update diriyahOpportunity;
        Quote diriyahQuote = RES_TestDataFactory.createQuote('Test Quote', diriyahOpportunity.Id, Test.getStandardPricebookId(), 'Customer Approved', quoteRecordTypeId);
        QuoteLineItem qli = RES_TestDataFactory.createQuoteLineItem(diriyahQuote.Id, 1, 100);
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
            RES_OpportunityStageUpdateValidation.Input inputObj = new RES_OpportunityStageUpdateValidation.Input();
            input.accountRecord = accountLst[0];
            input.opportunityRecord = [ SELECT Id, RecordTypeId, StageName
                                        FROM Opportunity 
                                        WHERE Name = 'Globant' ];
            input.quoteRecord = [ SELECT Id, RecordTypeId, Status, IsSyncing
                                  FROM Quote 
                                  WHERE OpportunityId =: input.opportunityRecord.Id ];
            inputs.add(input);
            inputObj.accountRecord = [ SELECT Id, RecordTypeId, BillingCountry, BillingStreet, BillingPostalCode, BillingCity, RES_CR_number__c, RES_Identification_Number__c
                                       FROM Account 
                                       WHERE Name = 'Diriyah' ];
            inputs.add(inputObj);
            RES_OpportunityStageUpdateValidation.validateOpportunity(inputs);
            List<Opportunity> oppLst = [ SELECT StageName
                                         FROM Opportunity 
                                         WHERE Name = 'Globant' AND 
                                         AccountId =: accountLst[0].Id ];
            if(!oppLst.isEmpty()){
                Assert.areEqual('Reservation', oppLst[0].StageName);
            }
        }
        Test.stopTest();
    }
}