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

    // NOTE: setting Opportunity.SyncedQuoteId (the only supported way to sync a Quote via
    // Apex) fires the org's real, already-active RES_Quote_After_Update_Update_Opportunity_Stage
    // flow, which itself calls RES_OpportunityStageUpdateValidation.validateOpportunity(). So the
    // "sync" tests below assert directly after that DML rather than also calling
    // validateOpportunity() a second time explicitly - a second manual call would re-run the
    // method against an already-updated Opportunity and hit a different (pre-existing) branch.

    @isTest
    public static void validateOpportunity_DraftQuoteSyncing_MovesToProposal(){
        Id quoteRecordTypeId = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Quote_Residential_Sales_RT)
            .getRecordTypeId();

        Account acc = RES_TestDataFactory.createCompanyRTAccount('Draft Sync Account', '9898989898');
        Opportunity opp = RES_TestDataFactory.createSingleBuyerOpportunity('Draft Sync Opp', acc.Id, 'Unit Selected', Date.Today().addDays(30), 'Amansamar Residences Wadi Safar');
        Quote draftQuote = RES_TestDataFactory.createQuote('Draft Sync Quote', opp.Id, Test.getStandardPricebookId(), 'Draft', quoteRecordTypeId);

        Test.startTest();
        opp.SyncedQuoteId = draftQuote.Id;
        update opp;
        Test.stopTest();

        Opportunity updatedOpp = [ SELECT StageName FROM Opportunity WHERE Id =: opp.Id ];
        Assert.areEqual('Proposal', updatedOpp.StageName, 'Draft quote becoming the syncing quote should move the Opportunity to Proposal');
    }

    @isTest
    public static void validateOpportunity_NegotiatingQuoteSyncing_MovesToUnitSelected(){
        Id quoteRecordTypeId = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Quote_Residential_Sales_RT)
            .getRecordTypeId();

        Account acc = RES_TestDataFactory.createCompanyRTAccount('Negotiating Sync Account', '9797979797');
        Opportunity opp = RES_TestDataFactory.createSingleBuyerOpportunity('Negotiating Sync Opp', acc.Id, 'Proposal', Date.Today().addDays(30), 'Amansamar Residences Wadi Safar');
        Quote negotiatingQuote = RES_TestDataFactory.createQuote('Negotiating Sync Quote', opp.Id, Test.getStandardPricebookId(), 'Negotiating', quoteRecordTypeId);

        Test.startTest();
        opp.SyncedQuoteId = negotiatingQuote.Id;
        update opp;
        Test.stopTest();

        Opportunity updatedOpp = [ SELECT StageName FROM Opportunity WHERE Id =: opp.Id ];
        Assert.areEqual('Unit Selected', updatedOpp.StageName, 'Negotiating quote becoming the syncing quote should move the Opportunity to Unit Selected');
    }

    @isTest
    public static void validateOpportunity_NonSyncingQuote_DoesNotChangeStage(){
        Id quoteRecordTypeId = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Quote_Residential_Sales_RT)
            .getRecordTypeId();

        // Starting stage is deliberately 'Unit Selected', not 'Proposal': the pre-existing
        // Proposal -> Unit Selected branch above fires unconditionally whenever this method
        // runs against a Proposal-stage Opportunity, regardless of the quote's sync state, so
        // starting at Proposal would collide with that branch instead of isolating this one.
        Account acc = RES_TestDataFactory.createCompanyRTAccount('Non Sync Account', '9696969696');
        Opportunity opp = RES_TestDataFactory.createSingleBuyerOpportunity('Non Sync Opp', acc.Id, 'Unit Selected', Date.Today().addDays(30), 'Amansamar Residences Wadi Safar');
        Quote nonSyncingQuote = RES_TestDataFactory.createQuote('Non Sync Quote', opp.Id, Test.getStandardPricebookId(), 'Draft', quoteRecordTypeId);
        // IsSyncing intentionally left false

        RES_OpportunityStageUpdateValidation.Input input = new RES_OpportunityStageUpdateValidation.Input();
        input.accountRecord = [ SELECT Id, RecordTypeId, BillingCountry, BillingStreet, BillingPostalCode, BillingCity, RES_CR_number__c, RES_Identification_Number__c FROM Account WHERE Id =: acc.Id ];
        input.opportunityRecord = [ SELECT Id, RecordTypeId, StageName FROM Opportunity WHERE Id =: opp.Id ];
        input.quoteRecord = nonSyncingQuote;

        Test.startTest();
        RES_OpportunityStageUpdateValidation.validateOpportunity(new List<RES_OpportunityStageUpdateValidation.Input>{ input });
        Test.stopTest();

        Opportunity updatedOpp = [ SELECT StageName FROM Opportunity WHERE Id =: opp.Id ];
        Assert.areEqual('Unit Selected', updatedOpp.StageName, 'A non-syncing quote should not trigger a stage change');
    }
}