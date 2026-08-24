@IsTest
private class RES_ProductOrchestratorTest {

    @TestSetup
    static void createTestData() {

        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;

        Id recordTypeId = Schema.SObjectType.Product2
            .getRecordTypeInfosByDeveloperName()
            .get('RES_Residential_Sales')
            .getRecordTypeId();

        Product2 product = new Product2(
            Name = 'Unit A101',
            IsActive = true,
            RES_Unit_Status__c = 'Available',
            RecordTypeId = recordTypeId,
            RES_HardBlock_Start__c = System.now()
        );
        insert product;

        Id standardPricebookId = Test.getStandardPricebookId();

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = product.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        // ------------------------------------------------------------
        // Opportunity 1 + Syncing Quote
        // ------------------------------------------------------------

        Opportunity opp1 = new Opportunity(
            Name = 'Test Opportunity 1',
            AccountId = acc.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = standardPricebookId
        );
        insert opp1;

        Quote quote1 = new Quote(
            Name = 'Test Quote 1',
            OpportunityId = opp1.Id,
            Pricebook2Id = standardPricebookId
        );
        insert quote1;

        QuoteLineItem qli1 = new QuoteLineItem(
            QuoteId = quote1.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert qli1;

        // Make Quote 1 the synced Quote.
        opp1.SyncedQuoteId = quote1.Id;
        update opp1;

        // ------------------------------------------------------------
        // Opportunity 2 + Non-syncing Quote
        // ------------------------------------------------------------

        Opportunity opp2 = new Opportunity(
            Name = 'Test Opportunity 2',
            AccountId = acc.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = standardPricebookId
        );
        insert opp2;

        Quote quote2 = new Quote(
            Name = 'Test Quote 2',
            OpportunityId = opp2.Id,
            Pricebook2Id = standardPricebookId
        );
        insert quote2;

        QuoteLineItem qli2 = new QuoteLineItem(
            QuoteId = quote2.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert qli2;
    }


    @IsTest
    static void testApplySoftHoldWithSyncingQuote() {

        Opportunity opp = [
            SELECT Id, SyncedQuoteId
            FROM Opportunity
            WHERE Name = 'Test Opportunity 1'
            LIMIT 1
        ];

        Quote syncingQuote = [
            SELECT Id, IsSyncing
            FROM Quote
            WHERE Name = 'Test Quote 1'
            LIMIT 1
        ];

        System.assertEquals(
            syncingQuote.Id,
            opp.SyncedQuoteId,
            'Test Quote 1 should be the synced Quote.'
        );

        System.assertEquals(
            true,
            syncingQuote.IsSyncing,
            'Test Quote 1 should be syncing.'
        );

        Test.startTest();

        RES_ProductOrchestrator.applySoftHold(
            new List<Opportunity>{ opp }
        );

        Test.stopTest();

        // ------------------------------------------------------------
        // Verify Product
        // ------------------------------------------------------------

        Product2 product = [
            SELECT
                RES_Unit_Status__c,
                RES_Soft_Hold_Start__c,
                RES_Soft_Hold_Until__c,
                RES_Reserved_By_Quote__c
            FROM Product2
            WHERE Name = 'Unit A101'
            LIMIT 1
        ];

        System.assertEquals(
            'Soft Hold',
            product.RES_Unit_Status__c,
            'Product should be moved to Soft Hold because the Quote is syncing.'
        );

        System.assertNotEquals(
            null,
            product.RES_Soft_Hold_Start__c,
            'Soft Hold Start should be populated.'
        );

        System.assertNotEquals(
            null,
            product.RES_Soft_Hold_Until__c,
            'Soft Hold Until should be populated.'
        );

        System.assertEquals(
            syncingQuote.Id,
            product.RES_Reserved_By_Quote__c,
            'Product should be reserved by the syncing Quote.'
        );

        // ------------------------------------------------------------
        // Verify other Quote using same Product is soft held
        // ------------------------------------------------------------

        Quote quote2 = [
            SELECT RES_Product_Soft_Held__c
            FROM Quote
            WHERE Name = 'Test Quote 2'
            LIMIT 1
        ];

        System.assertEquals(
            true,
            quote2.RES_Product_Soft_Held__c,
            'Other Quote using the same product should be soft held.'
        );
    }


    @IsTest
    static void testNonSyncingQuoteDoesNotSoftHoldProduct() {

        Opportunity opp = [
            SELECT Id, SyncedQuoteId
            FROM Opportunity
            WHERE Name = 'Test Opportunity 2'
            LIMIT 1
        ];

        Quote quote = [
            SELECT Id, IsSyncing
            FROM Quote
            WHERE Name = 'Test Quote 2'
            LIMIT 1
        ];

        System.assertEquals(
            null,
            opp.SyncedQuoteId,
            'Opportunity should not have a synced Quote.'
        );

        System.assertEquals(
            false,
            quote.IsSyncing,
            'Quote should not be syncing.'
        );

        Test.startTest();

        RES_ProductOrchestrator.applySoftHold(
            new List<Opportunity>{ opp }
        );

        Test.stopTest();

        // Product should NOT be soft held.
        Product2 product = [
            SELECT
                RES_Unit_Status__c,
                RES_Soft_Hold_Start__c,
                RES_Soft_Hold_Until__c,
                RES_Reserved_By_Quote__c
            FROM Product2
            WHERE Name = 'Unit A101'
            LIMIT 1
        ];

        System.assertEquals(
            'Available',
            product.RES_Unit_Status__c,
            'Product should remain Available when the Quote is not syncing.'
        );

        System.assertEquals(
            null,
            product.RES_Soft_Hold_Start__c,
            'Soft Hold Start should not be populated.'
        );

        System.assertEquals(
            null,
            product.RES_Soft_Hold_Until__c,
            'Soft Hold Until should not be populated.'
        );

        System.assertEquals(
            null,
            product.RES_Reserved_By_Quote__c,
            'Product should not be reserved by a non-syncing Quote.'
        );
    }


    @IsTest
    static void testNoQuoteLineItems() {

        Account acc = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Opportunity opp = new Opportunity(
            Name = 'Opportunity Without QLI',
            AccountId = acc.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert opp;

        Test.startTest();

        RES_ProductOrchestrator.applySoftHold(
            new List<Opportunity>{ opp }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM QuoteLineItem
                WHERE Quote.OpportunityId = :opp.Id
            ]
        );
    }


    @IsTest
    static void testEmptyOpportunityList() {

        Test.startTest();

        RES_ProductOrchestrator.applySoftHold(
            new List<Opportunity>()
        );

        Test.stopTest();

        System.assert(true);
    }


    @IsTest
    static void testMultipleOpportunities() {

        List<Opportunity> opps = [
            SELECT Id, SyncedQuoteId
            FROM Opportunity
            WHERE Name IN (
                'Test Opportunity 1',
                'Test Opportunity 2'
            )
        ];

        Test.startTest();

        RES_ProductOrchestrator.applySoftHold(opps);

        Test.stopTest();

        Product2 product = [
            SELECT
                RES_Unit_Status__c,
                RES_Soft_Hold_Start__c,
                RES_Soft_Hold_Until__c,
                RES_Reserved_By_Quote__c
            FROM Product2
            WHERE Name = 'Unit A101'
            LIMIT 1
        ];

        // Opportunity 1 has the syncing Quote,
        // therefore Product should be soft held.
        System.assertEquals(
            'Soft Hold',
            product.RES_Unit_Status__c,
            'Product should be soft held because one of the Quotes is syncing.'
        );

        System.assertNotEquals(
            null,
            product.RES_Soft_Hold_Start__c
        );

        System.assertNotEquals(
            null,
            product.RES_Soft_Hold_Until__c
        );

        System.assertNotEquals(
            null,
            product.RES_Reserved_By_Quote__c
        );
    }
}