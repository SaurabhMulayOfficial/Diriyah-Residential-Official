@IsTest
private class RES_OpportunityClosedLostServiceTest {

    @testSetup
    static void createTestData() {

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // =========================================================
        // Product / Unit
        // =========================================================
        Product2 product = new Product2(
            Name = 'Unit A101',
            IsActive = true,
            RES_Unit_Status__c = 'Hard Block',
            RES_HardBlock_Start__c = System.now()
        );
        insert product;

        // =========================================================
        // Standard Pricebook
        // =========================================================
        Id standardPricebookId = Test.getStandardPricebookId();

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = product.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        // =========================================================
        // Opportunity
        // =========================================================
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = standardPricebookId
        );
        insert opp;


        // =========================================================
        // Quote 1 - WITH Product
        // =========================================================
        Quote quote1 = new Quote(
            Name = 'Test Quote With Product',
            OpportunityId = opp.Id,
            Pricebook2Id = standardPricebookId,
            Status = 'Draft'
        );
        insert quote1;


        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = quote1.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert qli;


        // =========================================================
        // Quote 2 - WITHOUT Product
        // =========================================================
        Quote quote2 = new Quote(
            Name = 'Test Quote Without Product',
            OpportunityId = opp.Id,
            Pricebook2Id = standardPricebookId,
            Status = 'Draft'
        );
        insert quote2;
    }


    @IsTest
    static void testReleaseUnits() {
        Opportunity opp = [SELECT Id
            FROM Opportunity
            LIMIT 1
        ];

        RES_OpportunityClosedLostService.Input input =
            new RES_OpportunityClosedLostService.Input();
        input.opportunityId = opp.Id;
        Test.startTest();
        List<RES_OpportunityClosedLostService.Output> results =
            RES_OpportunityClosedLostService.releaseUnits(
                new List<RES_OpportunityClosedLostService.Input>{
                    input
                }
            );

        Test.stopTest();


        // =========================================================
        // Verify Output
        // =========================================================
        System.assertEquals(
            true,
            results[0].unitsReleased,
            'Unit should have been released.'
        );


        // =========================================================
        // Verify ALL Quotes Cancelled
        // =========================================================
        List<Quote> quotes = [
            SELECT Id, Status
            FROM Quote
            WHERE OpportunityId = :opp.Id
        ];


        System.assertEquals(
            2,
            quotes.size(),
            'Two Quotes should exist.'
        );


        for (Quote quote : quotes) {

            System.assertEquals(
                'Cancelled',
                quote.Status,
                'All Quotes related to Opportunity should be Cancelled.'
            );
        }


        // =========================================================
        // Verify Product Released
        // =========================================================
        Product2 product = [
            SELECT
                Id,
                RES_Unit_Status__c,
                RES_HardBlock_Start__c
            FROM Product2
            LIMIT 1
        ];


        System.assertEquals(
            'Available',
            product.RES_Unit_Status__c,
            'Hard Block unit should be changed to Available.'
        );


        System.assertEquals(
            null,
            product.RES_HardBlock_Start__c,
            'Hard Block Start should be cleared.'
        );
    }


    @IsTest
    static void testOpportunityIdNull() {

        RES_OpportunityClosedLostService.Input input =
            new RES_OpportunityClosedLostService.Input();

        input.opportunityId = null;


        Test.startTest();

        List<RES_OpportunityClosedLostService.Output> results =
            RES_OpportunityClosedLostService.releaseUnits(
                new List<RES_OpportunityClosedLostService.Input>{
                    input
                }
            );

        Test.stopTest();


        System.assertEquals(
            false,
            results[0].unitsReleased
        );
    }


    @IsTest
    static void testNullInput() {

        Test.startTest();

        List<RES_OpportunityClosedLostService.Output> results =
            RES_OpportunityClosedLostService.releaseUnits(null);

        Test.stopTest();


        System.assertEquals(
            false,
            results[0].unitsReleased
        );
    }


    @IsTest
    static void testEmptyInput() {

        Test.startTest();

        List<RES_OpportunityClosedLostService.Output> results =
            RES_OpportunityClosedLostService.releaseUnits(
                new List<RES_OpportunityClosedLostService.Input>()
            );

        Test.stopTest();


        System.assertEquals(
            false,
            results[0].unitsReleased
        );
    }


    @IsTest
    static void testInvalidOpportunity() {

        RES_OpportunityClosedLostService.Input input = new RES_OpportunityClosedLostService.Input();
        input.opportunityId =
            '006000000000000AAA';


        Test.startTest();
        List<RES_OpportunityClosedLostService.Output> results =
            RES_OpportunityClosedLostService.releaseUnits(
                new List<RES_OpportunityClosedLostService.Input>{
                    input
                }
            );

        Test.stopTest();
        System.assertEquals(
            false,
            results[0].unitsReleased
        );
    }


    @IsTest
    static void testBulkProcessing() {
        List<Opportunity> opps = [
            SELECT Id
            FROM Opportunity
        ];


        List<RES_OpportunityClosedLostService.Input> inputs = new List<RES_OpportunityClosedLostService.Input>();


        for (Opportunity opp : opps) {
            RES_OpportunityClosedLostService.Input input = new RES_OpportunityClosedLostService.Input();
            input.opportunityId = opp.Id;
            inputs.add(input);
        }


        Test.startTest();
        List<RES_OpportunityClosedLostService.Output> results =
            RES_OpportunityClosedLostService.releaseUnits(inputs);
        Test.stopTest();


        System.assertEquals(
            true,
            results[0].unitsReleased,
            'Unit should be released during bulk processing.'
        );
        // Verify Product
        List<Product2> products = [
            SELECT
                Id,
                RES_Unit_Status__c,
                RES_HardBlock_Start__c
            FROM Product2
        ];


        for (Product2 product : products) {
            System.assertEquals(
                'Available',
                product.RES_Unit_Status__c,
                'Product unit status should be Available.'
            );
            System.assertEquals(
                null,
                product.RES_HardBlock_Start__c,
                'Hard Block Start should be cleared.'
            );
        }


        // Verify Quotes
        List<Quote> quotes = [
            SELECT Id, Status
            FROM Quote
        ];
        for (Quote quote : quotes) {
            System.assertEquals(
                'Cancelled',
                quote.Status,
                'All related Quotes should be Cancelled.'
            );
        }
    }
}