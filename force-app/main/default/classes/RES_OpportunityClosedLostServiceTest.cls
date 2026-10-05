@IsTest
private class RES_OpportunityClosedLostServiceTest {

    // Not @testSetup - a class containing @testSetup can't have any method annotated
    // @isTest(SeeAllData=true), which the Service Charge Rate override methods below need
    // (to safely reuse the org's real AttributeDefinition rather than risk a duplicate
    // DeveloperName insert) - so this is called explicitly by each test that needs it instead.
    private static void createTestData() {

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
        Id standardPricebookId = resolvePricebookId();
        PricebookEntry pbe = insertTargetPricebookEntry(product.Id, 100);

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
        Account pendingAcc = new Account(Name = 'Pending Approval Test Account');
        insert pendingAcc;

        Opportunity pendingOpp = new Opportunity(
            Name = 'Pending Approval Test Opportunity',
            AccountId = pendingAcc.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = standardPricebookId
            );
        insert pendingOpp;

        Quote pendingQuote = new Quote(
            Name = 'Pending Approval Quote',
            OpportunityId = pendingOpp.Id,
            Pricebook2Id = standardPricebookId,
            Status = 'Pending Approval',
            RES_System_Status_Update__c = true
            );
        insert pendingQuote;
    }

    /** Resolves the Pricebook2Id to use for test Quotes/PricebookEntries. RES_Quote_Before_Insert_Set_Pricebook
     *  (a pre-existing, active flow) force-reassigns every new Quote's Pricebook2Id to whichever Pricebook2
     *  shares a Name with the Quote's (sole, default) RecordType - "Residential Sales" in this org. Under a
     *  plain @isTest context that real Pricebook2 is invisible (not SeeAllData), so the flow's lookup finds
     *  nothing and silently no-ops, leaving Test.getStandardPricebookId() as the only usable value. Under
     *  SeeAllData=true it IS visible, so the flow fires - this resolves to that same pricebook so the
     *  PricebookEntry/Quote/QuoteLineItem the test creates match what the flow will force anyway. */
    private static Id resolvePricebookId() {
        List<Pricebook2> residentialSalesPricebooks = [SELECT Id FROM Pricebook2 WHERE Name = 'Residential Sales' LIMIT 1];
        return residentialSalesPricebooks.isEmpty() ? Test.getStandardPricebookId() : residentialSalesPricebooks[0].Id;
    }

    /** The real Standard Price Book's Id - direct query works once SeeAllData=true makes it visible; falls back to
     *  Test.getStandardPricebookId() under a plain @isTest context where a direct Pricebook2 query returns 0 rows. */
    private static Id standardPricebookId() {
        List<Pricebook2> standardPricebooks = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        return standardPricebooks.isEmpty() ? Test.getStandardPricebookId() : standardPricebooks[0].Id;
    }

    /** Inserts and returns the PricebookEntry a Quote/QuoteLineItem should reference for this product, on
     *  whatever pricebook resolvePricebookId() targets. A custom (non-standard) pricebook entry requires a
     *  standard price to already exist for the same product/selling model/currency, so when the target
     *  pricebook isn't the Standard Price Book, a standard-priced entry is inserted first. */
    private static PricebookEntry insertTargetPricebookEntry(Id productId, Decimal unitPrice) {
        Id targetId = resolvePricebookId();
        Id standardId = standardPricebookId();
        if (targetId != standardId) {
            insert new PricebookEntry(Pricebook2Id = standardId, Product2Id = productId, UnitPrice = unitPrice, IsActive = true);
        }
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = targetId, Product2Id = productId, UnitPrice = unitPrice, IsActive = true);
        insert pbe;
        return pbe;
    }

    /** Configures the Service Charge Rate attribute override (RES_ProductSCRateValidation requires this before a Residential Sales unit can transition to Available) on the given product, reusing the org's real AttributeDefinition/ProductClassificationAttr - DeveloperName is unique org-wide, so this must run under SeeAllData=true. */
    private static void insertServiceChargeRateOverride(Id productId) {
        String scRateDeveloperName = Label.RES_Service_Charge_Rate_Attribute;

        List<AttributeDefinition> existingScRateAttrs = [
            SELECT Id FROM AttributeDefinition WHERE DeveloperName = :scRateDeveloperName LIMIT 1
        ];
        AttributeDefinition scRateAttr;
        if (!existingScRateAttrs.isEmpty()) {
            scRateAttr = existingScRateAttrs[0];
        } else {
            scRateAttr = new AttributeDefinition(
                Name = 'RES Test OppClosedLost SC Rate Attribute', Label = 'RES Test OppClosedLost SC Rate Attribute',
                DeveloperName = scRateDeveloperName, DataType = 'Number', IsActive = true
            );
            insert scRateAttr;
        }

        List<ProductClassificationAttr> existingClassificationAttrs = [
            SELECT Id, ProductClassificationId FROM ProductClassificationAttr WHERE AttributeDefinitionId = :scRateAttr.Id LIMIT 1
        ];
        ProductClassificationAttr classificationAttr;
        if (!existingClassificationAttrs.isEmpty()) {
            classificationAttr = existingClassificationAttrs[0];
        } else {
            ProductClassification classification = new ProductClassification(
                Code = 'RES_TEST_OPPCLOSEDLOST_' + String.valueOf(Crypto.getRandomInteger()).right(8),
                Name = 'RES Test OppClosedLost Classification',
                Status = 'Active'
            );
            insert classification;
            classificationAttr = new ProductClassificationAttr(
                Name = 'RES Test OppClosedLost Classification Attr',
                ProductClassificationId = classification.Id,
                AttributeDefinitionId = scRateAttr.Id
            );
            insert classificationAttr;
        }

        // Product2.BasedOnId must match the ProductClassificationAttr's own classification
        update new Product2(Id = productId, BasedOnId = classificationAttr.ProductClassificationId);

        insert new ProductAttributeDefinition(
            Name = 'RES Test OppClosedLost SC Rate Override',
            ProductClassificationAttributeId = classificationAttr.Id,
            Product2Id = productId,
            AttributeDefinitionId = scRateAttr.Id,
            DefaultValue = '120'
        );
    }


    @isTest(SeeAllData=true)
    static void testReleaseUnits() {
        createTestData();
        Product2 setupProduct = [SELECT Id FROM Product2 WHERE Name = 'Unit A101' LIMIT 1];
        insertServiceChargeRateOverride(setupProduct.Id);

        Opportunity opp = [SELECT Id
            FROM Opportunity
            WHERE Name = 'Test Opportunity'
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
            WHERE Name = 'Unit A101'
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


    @isTest(SeeAllData=true)
static void testBulkProcessing() {
    createTestData();
    Product2 setupProduct = [SELECT Id FROM Product2 WHERE Name = 'Unit A101' LIMIT 1];
    insertServiceChargeRateOverride(setupProduct.Id);

    // Scoped to this test's own Opportunity by name - under SeeAllData=true, the
    // previous "!= 'Pending Approval Test Opportunity'" pattern would match every
    // real Opportunity in the org instead of just this test's data
    List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE Name = 'Test Opportunity'];

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

    System.assertEquals(true,results[0].unitsReleased,'Unit should be released during bulk processing.');
    // Verify Product - scoped to this test's own product, not every product in the org
    List<Product2> products = [SELECT Id, RES_Unit_Status__c, RES_HardBlock_Start__c FROM Product2 WHERE Name = 'Unit A101'];
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

        // Verify Quotes — scoped to this test's own Opportunity by name, same reasoning as above
        List<Quote> quotes = [
            SELECT Id, Status
            FROM Quote
            WHERE OpportunityId IN (
                SELECT Id FROM Opportunity WHERE Name = 'Test Opportunity'
            )
        ];
        for (Quote quote : quotes) {
            System.assertEquals(
                'Cancelled',
                quote.Status,
                'All related Quotes should be Cancelled.'
            );
        }
    }


    // =============================================================
    // NEW TESTS — cover section 3b (product held elsewhere guard)
    // =============================================================

    @IsTest
    static void testProductStillHeldByAnotherOpportunity() {
        createTestData();
        Product2 product = [SELECT Id, RES_Unit_Status__c FROM Product2 WHERE Name = 'Unit A101' LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();

        // Second, unrelated Opportunity + Quote referencing the SAME product,
        // still active (not Cancelled)
        Account acc2 = new Account(Name = 'Test Account 2');
        insert acc2;

        Opportunity opp2 = new Opportunity(
            Name = 'Other Opportunity',
            AccountId = acc2.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = standardPricebookId
        );
        insert opp2;

        Quote quote2 = new Quote(
            Name = 'Other Quote Same Product',
            OpportunityId = opp2.Id,
            Pricebook2Id = standardPricebookId,
            Status = 'Draft'
        );
        insert quote2;

        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :product.Id LIMIT 1];
        insert new QuoteLineItem(
            QuoteId = quote2.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );

        // Now close the ORIGINAL Opportunity (the one from createTestData)
        Opportunity originalOpp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opportunity' LIMIT 1];

        RES_OpportunityClosedLostService.Input input = new RES_OpportunityClosedLostService.Input();
        input.opportunityId = originalOpp.Id;

        Test.startTest();
        RES_OpportunityClosedLostService.releaseUnits(
            new List<RES_OpportunityClosedLostService.Input>{ input }
        );
        Test.stopTest();

        // Product must NOT be released — still referenced by quote2 on opp2
        Product2 result = [SELECT RES_Unit_Status__c FROM Product2 WHERE Id = :product.Id];
        System.assertEquals(
            'Hard Block',
            result.RES_Unit_Status__c,
            'Product should remain held — still quoted on another active Opportunity.'
        );
    }

    @isTest(SeeAllData=true)
    static void testProductReleasedWhenOtherQuoteIsCancelled() {
        createTestData();
        Product2 product = [SELECT Id, RES_Unit_Status__c FROM Product2 WHERE Name = 'Unit A101' LIMIT 1];
        insertServiceChargeRateOverride(product.Id);
        Id standardPricebookId = resolvePricebookId();

        Account acc2 = new Account(Name = 'Test Account 3');
        insert acc2;

        Opportunity opp2 = new Opportunity(
            Name = 'Other Cancelled Opportunity',
            AccountId = acc2.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = standardPricebookId
        );
        insert opp2;

        Quote quote2 = new Quote(
            Name = 'Other Quote Already Cancelled',
            OpportunityId = opp2.Id,
            Pricebook2Id = standardPricebookId,
            Status = 'Draft' // Start as Draft to allow QuoteLineItem insertion
        );
        insert quote2;

        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :product.Id AND Pricebook2Id = :standardPricebookId LIMIT 1];
        insert new QuoteLineItem(
            QuoteId = quote2.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );

        // Now cancel the quote to test the scenario
        quote2.Status = 'Cancelled';
        quote2.RES_Cancellation_Reason__c = 'Test Cancellation';
        update quote2;

        Opportunity originalOpp = [SELECT Id FROM Opportunity WHERE Name = 'Test Opportunity' LIMIT 1];

        RES_OpportunityClosedLostService.Input input = new RES_OpportunityClosedLostService.Input();
        input.opportunityId = originalOpp.Id;

        Test.startTest();
        RES_OpportunityClosedLostService.releaseUnits(
            new List<RES_OpportunityClosedLostService.Input>{ input }
        );
        Test.stopTest();

        // Product should be released since the only other quote referencing it is cancelled
        Product2 result = [SELECT RES_Unit_Status__c FROM Product2 WHERE Id = :product.Id];
        System.assertEquals(
            'Available',
            result.RES_Unit_Status__c,
            'Product should be released — the only other quote is cancelled.'
        );
    }

    @isTest(SeeAllData=true)
    static void testContractsCancelledWhenOpportunityClosedLost() {
        Id standardPricebookId = resolvePricebookId();

        RES_IntegrationRequestEventService.batchSubmitter = new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        // Create a dedicated product for this test to avoid conflicts with setup data
        Product2 product = new Product2(
            Name = 'Unit Contract Test',
            IsActive = true,
            RES_Unit_Status__c = 'Hard Block',
            RES_HardBlock_Start__c = System.now()
        );
        insert product;
        insertServiceChargeRateOverride(product.Id);

        PricebookEntry pbe = insertTargetPricebookEntry(product.Id, 100);

        Account testAcc = new Account(Name = 'Test Account for Contract');
        insert testAcc;

        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity With Contract',
            AccountId = testAcc.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = standardPricebookId
        );
        insert testOpp;

        Quote testQuote = new Quote(
            Name = 'Test Quote With Contract',
            OpportunityId = testOpp.Id,
            Pricebook2Id = standardPricebookId,
            Status = 'Draft'
        );
        insert testQuote;

        insert new QuoteLineItem(
            QuoteId = testQuote.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );

        // Create a contract linked to this opportunity
        Contract testContract = new Contract(
            AccountId = testAcc.Id,
            SourceOpportunityId = testOpp.Id,
            Status = 'Draft',
            StartDate = Date.today(),
            ContractTerm = 12
        );
        insert testContract;

        RES_OpportunityClosedLostService.Input input = new RES_OpportunityClosedLostService.Input();
        input.opportunityId = testOpp.Id;

        Test.startTest();
        RES_OpportunityClosedLostService.releaseUnits(
            new List<RES_OpportunityClosedLostService.Input>{ input }
        );
        Test.stopTest();

        // Verify contract is cancelled
        Contract resultContract = [SELECT Status FROM Contract WHERE Id = :testContract.Id];
        System.assertEquals(
            'Canceled',
            resultContract.Status,
            'Contract should be cancelled when opportunity is closed lost.'
        );

        // Verify quote is cancelled
        Quote resultQuote = [SELECT Status FROM Quote WHERE Id = :testQuote.Id];
        System.assertEquals(
            'Cancelled',
            resultQuote.Status,
            'Quote should be cancelled when opportunity is closed lost.'
        );

        // Verify product is released
        Product2 resultProduct = [SELECT RES_Unit_Status__c FROM Product2 WHERE Id = :product.Id];
        System.assertEquals(
            'Available',
            resultProduct.RES_Unit_Status__c,
            'Product should be released when opportunity is closed lost.'
        );
    }


    // =============================================================
    // NEW TESTS — cover section 3a (pending approval identification)
    // =============================================================

    @IsTest
    static void testPendingApprovalQuoteWithNoLiveWorkItem() {
    createTestData();
    Opportunity pendingOpp = [
        SELECT Id FROM Opportunity WHERE Name = 'Pending Approval Test Opportunity' LIMIT 1
    ];
    Quote pendingQuote = [
        SELECT Id, Status FROM Quote WHERE OpportunityId = :pendingOpp.Id LIMIT 1
    ];

    RES_OpportunityClosedLostService.Input input = new RES_OpportunityClosedLostService.Input();
    input.opportunityId = pendingOpp.Id;

    Test.startTest();
    List<RES_OpportunityClosedLostService.Output> results =
        RES_OpportunityClosedLostService.releaseUnits(
            new List<RES_OpportunityClosedLostService.Input>{ input }
        );
    Test.stopTest();

    System.assertEquals(false, results[0].pendingApprovalQuotesFound,'No pending approval quotes found');
    System.assertEquals(0, results[0].pendingApprovalQuoteIds.size(),'No pending approval quote Ids found');
    System.assertEquals(0, results[0].pendingWorkItemIds.size(),'No pending work item Ids found');

    Quote unchanged = [SELECT Status FROM Quote WHERE Id = :pendingQuote.Id];
    System.assertEquals('Pending Approval', unchanged.Status,
        'Quote in Pending Approval must not be cancelled by this run.');
    }

    @IsTest
    static void testPendingApprovalQuoteWithLiveWorkItem() {
        createTestData();
        Opportunity pendingOpp = [
            SELECT Id FROM Opportunity WHERE Name = 'Pending Approval Test Opportunity' LIMIT 1
        ];
        Quote pendingQuote = [
            SELECT Id, Status FROM Quote WHERE OpportunityId = :pendingOpp.Id LIMIT 1
        ];

        ApprovalWorkItem fakeWorkItem = new ApprovalWorkItem(
            Id = '9jR000000000001AAA',
            RelatedRecordId = pendingQuote.Id,
            RelatedRecordObjectName = 'Quote',
            Status = 'Assigned'
        );
        RES_OpportunityClosedLostService.mockPendingApprovalWorkItems =
            new List<ApprovalWorkItem>{ fakeWorkItem };

        RES_OpportunityClosedLostService.Input input = new RES_OpportunityClosedLostService.Input();
        input.opportunityId = pendingOpp.Id;

        Test.startTest();
        List<RES_OpportunityClosedLostService.Output> results =
            RES_OpportunityClosedLostService.releaseUnits(
                new List<RES_OpportunityClosedLostService.Input>{ input }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].pendingApprovalQuotesFound,'Pending approval quotes should be found');
        System.assertEquals(1, results[0].pendingApprovalQuoteIds.size(),'One pending approval quote Id should be found');
        System.assertEquals(pendingQuote.Id, results[0].pendingApprovalQuoteIds[0],'Pending approval quote Id should match the expected quote');
        System.assertEquals(1, results[0].pendingWorkItemIds.size(),'One pending work item Id should be found');
        System.assertEquals('9jR000000000001AAA', results[0].pendingWorkItemIds[0],'Pending work item Id should match the expected work item');
    }
}