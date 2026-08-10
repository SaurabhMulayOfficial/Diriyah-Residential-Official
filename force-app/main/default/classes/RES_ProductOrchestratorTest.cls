@IsTest
private class RES_ProductOrchestratorTest {

    @TestSetup
    static void createTestData() {

        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;

        Product2 product = new Product2(
            Name = 'Unit A101',
            IsActive = true,
            RES_Unit_Status__c = 'Available',
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
    static void testApplySoftHold() {

        Opportunity opp = [
            SELECT Id
            FROM Opportunity
            WHERE Name = 'Test Opportunity 1'
            LIMIT 1
        ];

        Test.startTest();

        RES_ProductOrchestrator.applySoftHold(
            new List<Opportunity>{ opp }
        );

        Test.stopTest();

        // Verify Product
        Product2 product = [
            SELECT
                RES_Unit_Status__c,
                RES_Soft_Hold_Start__c,
                RES_Soft_Hold_Until__c
            FROM Product2
            WHERE Name = 'Unit A101'
            LIMIT 1
        ];

        System.assertEquals(
            'Soft Hold',
            product.RES_Unit_Status__c,
            'Product should be moved to Soft Hold.'
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

        System.assert(
            product.RES_Soft_Hold_Until__c >
            product.RES_Soft_Hold_Start__c,
            'Soft Hold Until should be after Soft Hold Start.'
        );


        // Verify Quote belonging to another Opportunity
        // using the same product.
        Quote quote2 = [
            SELECT
                RES_Product_Soft_Held__c
            FROM Quote
            WHERE Name = 'Test Quote 2'
            LIMIT 1
        ];

        System.assertEquals(
            true,
            quote2.RES_Product_Soft_Held__c,
            'Quote for another Opportunity using the same product should be soft held.'
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

        // Nothing should be processed.
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
            SELECT Id
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
                RES_Soft_Hold_Until__c
            FROM Product2
            WHERE Name = 'Unit A101'
            LIMIT 1
        ];

        System.assertEquals(
            'Soft Hold',
            product.RES_Unit_Status__c
        );

        System.assertNotEquals(
            null,
            product.RES_Soft_Hold_Start__c
        );

        System.assertNotEquals(
            null,
            product.RES_Soft_Hold_Until__c
        );
    }
}
