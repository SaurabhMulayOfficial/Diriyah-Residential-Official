@isTest
public class RES_OpportunityStageUpdateValidationTest {

    @testSetup
    public static void setupTestData() {

        Test.startTest();

        Id quoteRecordTypeId = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Quote_Residential_Sales_RT)
            .getRecordTypeId();

        Account companyAccount = RES_TestDataFactory.createCompanyRTAccount(
            'Globant',
            '1212121212'
        );

        Opportunity singleOpportunity = RES_TestDataFactory.createSingleBuyerOpportunity(
            'Globant',
            companyAccount.Id,
            'Proposal',
            Date.today(),
            'Amansamar Residences Wadi Safar'
        );

        Quote quoteObj = RES_TestDataFactory.createQuote(
            'Test Quote',
            singleOpportunity.Id,
            Test.getStandardPricebookId(),
            'Draft',
            quoteRecordTypeId
        );

        // Create QLI before approving the Quote
        RES_TestDataFactory.createQuoteLineItem(
            quoteObj.Id,
            1,
            100
        );

        // Sync Quote
        singleOpportunity.SyncedQuoteId = quoteObj.Id;
        update singleOpportunity;

        // Approve Quote
        update new Quote(
            Id = quoteObj.Id,
            Status = 'Customer Approved'
        );

        Account diriyahAccount = RES_TestDataFactory.createCompanyRTAccount(
            'Diriyah',
            '3434343434'
        );

        Opportunity diriyahOpportunity = RES_TestDataFactory.createSingleBuyerOpportunity(
            'Diriyah',
            diriyahAccount.Id,
            'Unit Selected',
            Date.today().addDays(30),
            'Amansamar Residences Wadi Safar'
        );

        diriyahOpportunity.Pricebook2Id = Test.getStandardPricebookId();
        update diriyahOpportunity;

        Quote diriyahQuote = RES_TestDataFactory.createQuote(
            'Test Quote',
            diriyahOpportunity.Id,
            Test.getStandardPricebookId(),
            'Draft',
            quoteRecordTypeId
        );

        // Create QLI before approving the Quote
        RES_TestDataFactory.createQuoteLineItem(
            diriyahQuote.Id,
            1,
            100
        );

        // Sync Quote
        diriyahOpportunity.SyncedQuoteId = diriyahQuote.Id;
        update diriyahOpportunity;

        // Approve Quote
        update new Quote(
            Id = diriyahQuote.Id,
            Status = 'Customer Approved'
        );

        Test.stopTest();
    }

    @isTest
    public static void validateOpportunityTest() {

        Test.startTest();

        List<RES_OpportunityStageUpdateValidation.Input> inputs =
            new List<RES_OpportunityStageUpdateValidation.Input>();

        List<Account> accountLst = [
            SELECT Id,
                   RecordTypeId,
                   BillingCountry,
                   BillingStreet,
                   BillingPostalCode,
                   BillingCity,
                   RES_CR_number__c,
                   RES_Identification_Number__c
            FROM Account
            WHERE Name = 'Globant'
        ];

        if (!accountLst.isEmpty()) {

            RES_OpportunityStageUpdateValidation.Input input =
                new RES_OpportunityStageUpdateValidation.Input();

            RES_OpportunityStageUpdateValidation.Input inputObj =
                new RES_OpportunityStageUpdateValidation.Input();

            input.accountRecord = accountLst[0];

            input.opportunityRecord = [
                SELECT Id,
                       RecordTypeId,
                       StageName
                FROM Opportunity
                WHERE Name = 'Globant'
                LIMIT 1
            ];

            input.quoteRecord = [
                SELECT Id,
                       RecordTypeId,
                       Status,
                       IsSyncing
                FROM Quote
                WHERE OpportunityId = :input.opportunityRecord.Id
                LIMIT 1
            ];

            inputs.add(input);

            inputObj.accountRecord = [
                SELECT Id,
                       RecordTypeId,
                       BillingCountry,
                       BillingStreet,
                       BillingPostalCode,
                       BillingCity,
                       RES_CR_number__c,
                       RES_Identification_Number__c
                FROM Account
                WHERE Name = 'Diriyah'
                LIMIT 1
            ];

            inputs.add(inputObj);

            RES_OpportunityStageUpdateValidation.validateOpportunity(inputs);

            List<Opportunity> oppLst = [
                SELECT StageName
                FROM Opportunity
                WHERE Name = 'Globant'
                AND AccountId = :accountLst[0].Id
            ];

            if (!oppLst.isEmpty()) {
                Assert.areEqual(
                    'Reservation',
                    oppLst[0].StageName
                );
            }
        }

        Test.stopTest();
    }

    @isTest
    public static void validateOpportunity_DraftQuoteSyncing_MovesToProposal() {

        Id quoteRecordTypeId = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Quote_Residential_Sales_RT)
            .getRecordTypeId();

        Account acc = RES_TestDataFactory.createCompanyRTAccount(
            'Draft Sync Account',
            '9898989898'
        );

        Opportunity opp = RES_TestDataFactory.createSingleBuyerOpportunity(
            'Draft Sync Opp',
            acc.Id,
            'Unit Selected',
            Date.today().addDays(30),
            'Amansamar Residences Wadi Safar'
        );

        Quote draftQuote = RES_TestDataFactory.createQuote(
            'Draft Sync Quote',
            opp.Id,
            Test.getStandardPricebookId(),
            'Draft',
            quoteRecordTypeId
        );

        // Create QLI for the Quote
        RES_TestDataFactory.createQuoteLineItem(
            draftQuote.Id,
            1,
            100
        );

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        Assert.areEqual(
            'Proposal',
            updatedOpp.StageName,
            'Draft quote becoming the syncing quote should move the Opportunity to Proposal'
        );
    }

    @isTest
    public static void validateOpportunity_NegotiatingQuoteWithLineItemSyncing_MovesToUnitSelected() {

        Id quoteRecordTypeId = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Quote_Residential_Sales_RT)
            .getRecordTypeId();

        Account acc = RES_TestDataFactory.createCompanyRTAccount(
            'Negotiating Sync Account',
            '9797979797'
        );

        Opportunity opp = RES_TestDataFactory.createSingleBuyerOpportunity(
            'Negotiating Sync Opp',
            acc.Id,
            'Proposal',
            Date.today().addDays(30),
            'Amansamar Residences Wadi Safar'
        );

        Quote negotiatingQuote = RES_TestDataFactory.createQuote(
            'Negotiating Sync Quote',
            opp.Id,
            Test.getStandardPricebookId(),
            'Negotiating',
            quoteRecordTypeId
        );

        // Create QLI
        RES_TestDataFactory.createQuoteLineItem(
            negotiatingQuote.Id,
            1,
            100
        );

        Test.startTest();

        opp.SyncedQuoteId = negotiatingQuote.Id;
        update opp;

        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        Assert.areEqual(
            'Unit Selected',
            updatedOpp.StageName,
            'Negotiating quote with a line item becoming the syncing quote should move the Opportunity to Unit Selected'
        );
    }

    @isTest
    public static void validateOpportunity_NegotiatingQuoteWithoutLineItemSyncing_MovesToProposal() {

        Id quoteRecordTypeId = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Quote_Residential_Sales_RT)
            .getRecordTypeId();

        Account acc = RES_TestDataFactory.createCompanyRTAccount(
            'Negotiating No Line Item Account',
            '9595959595'
        );

        Opportunity opp = RES_TestDataFactory.createSingleBuyerOpportunity(
            'Negotiating No Line Item Opp',
            acc.Id,
            'Proposal',
            Date.today().addDays(30),
            'Amansamar Residences Wadi Safar'
        );

        Quote negotiatingQuote = RES_TestDataFactory.createQuote(
            'Negotiating No Line Item Quote',
            opp.Id,
            Test.getStandardPricebookId(),
            'Negotiating',
            quoteRecordTypeId
        );

        /*
         * Intentionally do NOT create a QLI.
         * This test validates the behavior of a Negotiating Quote
         * without a Quote Line Item.
         */

        Test.startTest();

        opp.SyncedQuoteId = negotiatingQuote.Id;
        update opp;

        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        Assert.areEqual(
            'Proposal',
            updatedOpp.StageName,
            'A Negotiating quote with no line items should move the Opportunity to Proposal'
        );
    }

    @isTest
    public static void validateOpportunity_NonSyncingQuote_DoesNotChangeStage() {

        Id quoteRecordTypeId = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Quote_Residential_Sales_RT)
            .getRecordTypeId();

        Account acc = RES_TestDataFactory.createCompanyRTAccount(
            'Non Sync Account',
            '9696969696'
        );

        Opportunity opp = RES_TestDataFactory.createSingleBuyerOpportunity(
            'Non Sync Opp',
            acc.Id,
            'Unit Selected',
            Date.today().addDays(30),
            'Amansamar Residences Wadi Safar'
        );

        Quote nonSyncingQuote = RES_TestDataFactory.createQuote(
            'Non Sync Quote',
            opp.Id,
            Test.getStandardPricebookId(),
            'Draft',
            quoteRecordTypeId
        );

        // Create QLI
        RES_TestDataFactory.createQuoteLineItem(
            nonSyncingQuote.Id,
            1,
            100
        );

        Opportunity baselineOpp = [
            SELECT RecordTypeId,
                   StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        RES_OpportunityStageUpdateValidation.Input input =
            new RES_OpportunityStageUpdateValidation.Input();

        input.accountRecord = [
            SELECT Id,
                   RecordTypeId,
                   BillingCountry,
                   BillingStreet,
                   BillingPostalCode,
                   BillingCity,
                   RES_CR_number__c,
                   RES_Identification_Number__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        input.opportunityRecord = baselineOpp;
        input.quoteRecord = nonSyncingQuote;

        Test.startTest();

        RES_OpportunityStageUpdateValidation.validateOpportunity(
            new List<RES_OpportunityStageUpdateValidation.Input>{
                input
            }
        );

        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        Assert.areEqual(
            baselineOpp.StageName,
            updatedOpp.StageName,
            'A non-syncing quote should not trigger any further stage change'
        );
    }
}