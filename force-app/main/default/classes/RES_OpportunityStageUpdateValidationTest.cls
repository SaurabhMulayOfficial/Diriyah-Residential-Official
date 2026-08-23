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
    public static void validateOpportunity_NegotiatingQuoteWithLineItemSyncing_MovesToUnitSelected(){
        Id quoteRecordTypeId = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Quote_Residential_Sales_RT)
            .getRecordTypeId();

        Account acc = RES_TestDataFactory.createCompanyRTAccount('Negotiating Sync Account', '9797979797');
        Opportunity opp = RES_TestDataFactory.createSingleBuyerOpportunity('Negotiating Sync Opp', acc.Id, 'Proposal', Date.Today().addDays(30), 'Amansamar Residences Wadi Safar');
        Quote negotiatingQuote = RES_TestDataFactory.createQuote('Negotiating Sync Quote', opp.Id, Test.getStandardPricebookId(), 'Negotiating', quoteRecordTypeId);
        // RES_Quote_Before_Insert_Set_Pricebook overrides Quote.Pricebook2Id based on the
        // Opportunity's project, so a PricebookEntry built against the standard pricebook alone
        // won't match - re-query the quote's actual assigned pricebook and build entries for both
        // (a standard-pricebook entry is required to exist before a product can appear in a
        // custom one), matching the pattern that resolved this same mismatch during manual
        // reproduction earlier in this session.
        negotiatingQuote = [ SELECT Id, Pricebook2Id FROM Quote WHERE Id =: negotiatingQuote.Id ];
        Product2 unit = RES_TestDataFactory.createProduct('Negotiating Sync Unit');
        // Quote Sync rejects products still at the default RES_Unit_Status__c of 'Draft' as not
        // sale-ready ("inactive or archived products"), so mark it Available before syncing.
        unit.RES_Unit_Status__c = 'Available';
        update unit;
        // Some org automation auto-creates a standard PricebookEntry on Product2 insert, so check
        // before inserting one ourselves rather than assuming it doesn't exist yet.
        List<PricebookEntry> existingStdPbe = [ SELECT Id, Pricebook2Id FROM PricebookEntry WHERE Product2Id =: unit.Id AND Pricebook2Id =: Test.getStandardPricebookId() ];
        if(existingStdPbe.isEmpty()){
            insert new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = unit.Id, UnitPrice = 100, IsActive = true);
        }
        PricebookEntry quotePbe;
        if(negotiatingQuote.Pricebook2Id == Test.getStandardPricebookId()){
            quotePbe = existingStdPbe.isEmpty() ? [ SELECT Id FROM PricebookEntry WHERE Product2Id =: unit.Id AND Pricebook2Id =: Test.getStandardPricebookId() LIMIT 1 ] : existingStdPbe[0];
        } else {
            quotePbe = new PricebookEntry(Pricebook2Id = negotiatingQuote.Pricebook2Id, Product2Id = unit.Id, UnitPrice = 100, IsActive = true);
            insert quotePbe;
        }
        insert new QuoteLineItem(QuoteId = negotiatingQuote.Id, PricebookEntryId = quotePbe.Id, Quantity = 1, UnitPrice = 100);

        Test.startTest();
        opp.SyncedQuoteId = negotiatingQuote.Id;
        update opp;
        Test.stopTest();

        Opportunity updatedOpp = [ SELECT StageName FROM Opportunity WHERE Id =: opp.Id ];
        Assert.areEqual('Unit Selected', updatedOpp.StageName, 'Negotiating quote with a line item becoming the syncing quote should move the Opportunity to Unit Selected');
    }

    @isTest
    public static void validateOpportunity_NegotiatingQuoteWithoutLineItemSyncing_MovesToProposal(){
        Id quoteRecordTypeId = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Quote_Residential_Sales_RT)
            .getRecordTypeId();

        Account acc = RES_TestDataFactory.createCompanyRTAccount('Negotiating No Line Item Account', '9595959595');
        Opportunity opp = RES_TestDataFactory.createSingleBuyerOpportunity('Negotiating No Line Item Opp', acc.Id, 'Proposal', Date.Today().addDays(30), 'Amansamar Residences Wadi Safar');
        Quote negotiatingQuote = RES_TestDataFactory.createQuote('Negotiating No Line Item Quote', opp.Id, Test.getStandardPricebookId(), 'Negotiating', quoteRecordTypeId);
        // No QuoteLineItem inserted - no unit has actually been selected on this quote

        Test.startTest();
        opp.SyncedQuoteId = negotiatingQuote.Id;
        update opp;
        Test.stopTest();

        Opportunity updatedOpp = [ SELECT StageName FROM Opportunity WHERE Id =: opp.Id ];
        Assert.areEqual('Proposal', updatedOpp.StageName, 'A Unit-Selected-eligible quote with no line items should move the Opportunity to Proposal, not Unit Selected');
    }

    @isTest
    public static void validateOpportunity_NonSyncingQuote_DoesNotChangeStage(){
        Id quoteRecordTypeId = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Quote_Residential_Sales_RT)
            .getRecordTypeId();

        Account acc = RES_TestDataFactory.createCompanyRTAccount('Non Sync Account', '9696969696');
        Opportunity opp = RES_TestDataFactory.createSingleBuyerOpportunity('Non Sync Opp', acc.Id, 'Unit Selected', Date.Today().addDays(30), 'Amansamar Residences Wadi Safar');
        Quote nonSyncingQuote = RES_TestDataFactory.createQuote('Non Sync Quote', opp.Id, Test.getStandardPricebookId(), 'Draft', quoteRecordTypeId);
        // IsSyncing intentionally left false

        // Inserting the Quote above already triggers other, unrelated org automation that can move
        // the Opportunity's stage on its own (confirmed empirically: a freshly inserted, non-syncing
        // Quote alone moves the Opportunity to 'Proposal', independent of this class). So the stage
        // right after that insert - not the stage at creation - is the correct baseline: this test
        // isolates whether calling validateOpportunity() with a non-syncing quote causes any FURTHER
        // change on top of that baseline, not whether the Opportunity's stage is frozen outright.
        Opportunity baselineOpp = [ SELECT RecordTypeId, StageName FROM Opportunity WHERE Id =: opp.Id ];

        RES_OpportunityStageUpdateValidation.Input input = new RES_OpportunityStageUpdateValidation.Input();
        input.accountRecord = [ SELECT Id, RecordTypeId, BillingCountry, BillingStreet, BillingPostalCode, BillingCity, RES_CR_number__c, RES_Identification_Number__c FROM Account WHERE Id =: acc.Id ];
        input.opportunityRecord = baselineOpp;
        input.quoteRecord = nonSyncingQuote;

        Test.startTest();
        RES_OpportunityStageUpdateValidation.validateOpportunity(new List<RES_OpportunityStageUpdateValidation.Input>{ input });
        Test.stopTest();

        Opportunity updatedOpp = [ SELECT StageName FROM Opportunity WHERE Id =: opp.Id ];
        Assert.areEqual(baselineOpp.StageName, updatedOpp.StageName, 'A non-syncing quote should not trigger any further stage change on top of whatever the Opportunity was already at');
    }
}