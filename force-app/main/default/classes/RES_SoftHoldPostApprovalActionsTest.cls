@IsTest
private class RES_SoftHoldPostApprovalActionsTest {

    // Holds the Ids createTestData() creates, so SeeAllData=true callers never have to
    // re-query generic fixture Names (e.g. 'Unit A102', 'Test Quote 2') - those aren't
    // guaranteed unique against real org data, making a LIMIT 1 re-query non-deterministic.
    private class TestDataIds {
        Id product1Id;
        Id product2Id;
        Id product3Id;
        Id quote1Id;
        Id quote2Id;
        Id quote3Id;
    }

    /** Not @TestSetup: testApproveExpiredSoftHold/testRejectExpiredSoftHold need SeeAllData=true to safely reuse the org's real Service Charge Rate AttributeDefinition, and a class can't mix @TestSetup with any SeeAllData=true method. Every test method calls this explicitly instead. */
    static TestDataIds createTestData() {
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        config.RES_Triggers_Off__c = true;
        upsert config;

        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;

        Id targetPricebookId = resolvePricebookId();

        Id recordTypeId = Schema.SObjectType.Product2
            .getRecordTypeInfosByDeveloperName()
            .get('RES_Residential_Sales')
            .getRecordTypeId();

        // Product 1 - used for Approve/Future Extension
        Product2 product1 = new Product2(
            Name = 'Unit A101',
            IsActive = true,
            RES_Unit_Status__c = 'Soft Hold',
            RES_Soft_Hold_Until__c = System.now().addHours(2),
            RES_Is_In_Soft_Hold_Extension__c = true,
            recordTypeId = recordTypeId
        );

        // Product 2 - used for Approve/Expired Extension
        Product2 product2 = new Product2(
            Name = 'Unit A102',
            IsActive = true,
            RES_Unit_Status__c = 'Soft Hold',
            RES_Soft_Hold_Until__c = System.now().addHours(-2),
            RES_Is_In_Soft_Hold_Extension__c = true
        );

        // Product 3 - used for Reject/Expired Soft Hold
        Product2 product3 = new Product2(
            Name = 'Unit A103',
            IsActive = true,
            RES_Unit_Status__c = 'Soft Hold',
            RES_Soft_Hold_Until__c = System.now().addHours(-2),
            RES_Is_In_Soft_Hold_Extension__c = true
        );

        insert new List<Product2>{
            product1,
            product2,
            product3
        };

        List<PricebookEntry> pbes = new List<PricebookEntry>();
        pbes.add(insertTargetPricebookEntry(product1.Id, 100));
        pbes.add(insertTargetPricebookEntry(product2.Id, 100));
        pbes.add(insertTargetPricebookEntry(product3.Id, 100));

        // Opportunity 1
        Opportunity opp1 = new Opportunity(
            Name = 'Test Opportunity 1',
            AccountId = acc.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = targetPricebookId
        );
        insert opp1;

        // Opportunity 2
        Opportunity opp2 = new Opportunity(
            Name = 'Test Opportunity 2',
            AccountId = acc.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = targetPricebookId
        );
        insert opp2;

        // Opportunity 3
        Opportunity opp3 = new Opportunity(
            Name = 'Test Opportunity 3',
            AccountId = acc.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = targetPricebookId
        );
        insert opp3;

        // Quotes
        Quote quote1 = new Quote(
            Name = 'Test Quote 1',
            OpportunityId = opp1.Id,
            Pricebook2Id = targetPricebookId,
            RES_Extend_Soft_Hold_By_Hours__c = 8
        );

        Quote quote2 = new Quote(
            Name = 'Test Quote 2',
            OpportunityId = opp2.Id,
            Pricebook2Id = targetPricebookId,
            RES_Extend_Soft_Hold_By_Hours__c = 8
        );

        Quote quote3 = new Quote(
            Name = 'Test Quote 3',
            OpportunityId = opp3.Id,
            Pricebook2Id = targetPricebookId,
            RES_Extend_Soft_Hold_By_Hours__c = 8
        );

        insert new List<Quote>{
            quote1,
            quote2,
            quote3
        };

        // QLI for Product 1
        QuoteLineItem qli1 = new QuoteLineItem(
            QuoteId = quote1.Id,
            PricebookEntryId = pbes[0].Id,
            Quantity = 1,
            UnitPrice = 100
        );

        // QLI for Product 2
        QuoteLineItem qli2 = new QuoteLineItem(
            QuoteId = quote2.Id,
            PricebookEntryId = pbes[1].Id,
            Quantity = 1,
            UnitPrice = 100
        );

        // QLI for Product 3
        QuoteLineItem qli3 = new QuoteLineItem(
            QuoteId = quote3.Id,
            PricebookEntryId = pbes[2].Id,
            Quantity = 1,
            UnitPrice = 100
        );

        insert new List<QuoteLineItem>{
            qli1,
            qli2,
            qli3
        };

        TestDataIds ids = new TestDataIds();
        ids.product1Id = product1.Id;
        ids.product2Id = product2.Id;
        ids.product3Id = product3.Id;
        ids.quote1Id = quote1.Id;
        ids.quote2Id = quote2.Id;
        ids.quote3Id = quote3.Id;
        return ids;
    }

    /** Resolves the Pricebook2Id to use for test Quotes/PricebookEntries. RES_Quote_Before_Insert_Set_Pricebook (a pre-existing, active flow) force-reassigns every new Quote's Pricebook2Id to whichever Pricebook2 shares a Name with the Quote's (sole, default) RecordType - "Residential Sales" in this org. Under a plain @isTest context that real Pricebook2 is invisible (not SeeAllData), so the flow's lookup finds nothing and silently no-ops, leaving Test.getStandardPricebookId() as the only usable value. Under SeeAllData=true it IS visible, so the flow fires - this resolves to that same pricebook so the PricebookEntry/Quote/QuoteLineItem the test creates match what the flow will force anyway. */
    private static Id resolvePricebookId() {
        List<Pricebook2> residentialSalesPricebooks = [SELECT Id FROM Pricebook2 WHERE Name = 'Residential Sales' LIMIT 1];
        return residentialSalesPricebooks.isEmpty() ? Test.getStandardPricebookId() : residentialSalesPricebooks[0].Id;
    }

    /** The real Standard Price Book's Id - direct query works once SeeAllData=true makes it visible; falls back to Test.getStandardPricebookId() under a plain @isTest context where a direct Pricebook2 query returns 0 rows. */
    private static Id standardPricebookId() {
        List<Pricebook2> standardPricebooks = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        return standardPricebooks.isEmpty() ? Test.getStandardPricebookId() : standardPricebooks[0].Id;
    }

    /** Inserts and returns the PricebookEntry a Quote/QuoteLineItem should reference for this product, on whatever pricebook resolvePricebookId() targets. A custom (non-standard) pricebook entry requires a standard price to already exist for the same product/selling model/currency, so when the target pricebook isn't the Standard Price Book, a standard-priced entry is inserted first. */
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

    /** Configures the Service Charge Rate attribute override (RES_ProductSCRateValidation requires this before a Residential Sales unit can go Available) on the given product, reusing the org's real AttributeDefinition/ProductClassificationAttr - DeveloperName is unique org-wide, so this must run under SeeAllData=true. */
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
                Name = 'RES Test SoftHold SC Rate Attribute', Label = 'RES Test SoftHold SC Rate Attribute',
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
                Code = 'RES_TEST_SOFTHOLD_' + String.valueOf(Crypto.getRandomInteger()).right(8),
                Name = 'RES Test SoftHold Classification',
                Status = 'Active'
            );
            insert classification;
            classificationAttr = new ProductClassificationAttr(
                Name = 'RES Test SoftHold Classification Attr',
                ProductClassificationId = classification.Id,
                AttributeDefinitionId = scRateAttr.Id
            );
            insert classificationAttr;
        }

        // Product2.BasedOnId must match the ProductClassificationAttr's own classification
        update new Product2(Id = productId, BasedOnId = classificationAttr.ProductClassificationId);

        insert new ProductAttributeDefinition(
            Name = 'RES Test SoftHold SC Rate Override',
            ProductClassificationAttributeId = classificationAttr.Id,
            Product2Id = productId,
            AttributeDefinitionId = scRateAttr.Id,
            DefaultValue = '120'
        );
    }


    /**
     * Approve:
     *
     * Soft Hold Until = future
     * Extension = 8 hours
     *
     * Expected:
     * - RES_Soft_Hold_Until__c gets extended
     * - RES_Is_In_Soft_Hold_Extension__c = false
     * - Unit remains in Soft Hold
     */
    @IsTest
    static void testApproveFutureSoftHold() {
        createTestData();

        Quote quote = [
            SELECT Id,
                    RES_Extend_Soft_Hold_By_Hours__c
            FROM Quote
            WHERE Name = 'Test Quote 1'
            LIMIT 1
        ];

        Product2 productBefore = [
            SELECT Id,
                    RES_Soft_Hold_Until__c
            FROM Product2
            WHERE Name = 'Unit A101'
            LIMIT 1
        ];

        DateTime oldSoftHoldUntil = productBefore.RES_Soft_Hold_Until__c;

        RES_SoftHoldPostApprovalActions.input inputObj =
            new RES_SoftHoldPostApprovalActions.input();

        inputObj.quote = quote;
        inputObj.action = 'Approve';

        Test.startTest();

        RES_SoftHoldPostApprovalActions.executeSoftHoldPostApprovalActions(
            new List<RES_SoftHoldPostApprovalActions.input>{
                inputObj
            }
        );

        Test.stopTest();

        Product2 productAfter = [
            SELECT Id,
                    RES_Unit_Status__c,
                    RES_Soft_Hold_Until__c,
                    RES_Is_In_Soft_Hold_Extension__c
            FROM Product2
            WHERE Id = :productBefore.Id
        ];

        System.assertEquals(
            false,
            productAfter.RES_Is_In_Soft_Hold_Extension__c,
            'Soft Hold Extension flag should be false.'
        );

        System.assertEquals(
            'Soft Hold',
            productAfter.RES_Unit_Status__c,
            'Product should remain in Soft Hold.'
        );

        System.assert(
            productAfter.RES_Soft_Hold_Until__c > oldSoftHoldUntil,
            'Soft Hold Until should be extended.'
        );
    }


    /**
     * Approve:
     *
     * Soft Hold Until = expired
     *
     * After adding extension, the date is still expected
     * to be evaluated against DateTime.now().
     *
     * Expected:
     * Product becomes Available if the resulting date
     * is not in the future.
     */
    @IsTest(SeeAllData=true)
    static void testApproveExpiredSoftHold() {
        TestDataIds ids = createTestData();

        Quote quote = [
            SELECT Id,
                    RES_Extend_Soft_Hold_By_Hours__c
            FROM Quote
            WHERE Id = :ids.quote2Id
        ];

        insertServiceChargeRateOverride(ids.product2Id);

        // Make the extension sufficiently negative/short so
        // the resulting date is in the past.
        quote.RES_Extend_Soft_Hold_By_Hours__c = 0;
        update quote;

        RES_SoftHoldPostApprovalActions.input inputObj =
            new RES_SoftHoldPostApprovalActions.input();

        inputObj.quote = quote;
        inputObj.action = 'Approve';

        Test.startTest();

        RES_SoftHoldPostApprovalActions.executeSoftHoldPostApprovalActions(
            new List<RES_SoftHoldPostApprovalActions.input>{
                inputObj
            }
        );

        Test.stopTest();

        Product2 product = [
            SELECT Id,
                    RES_Unit_Status__c,
                    RES_Is_In_Soft_Hold_Extension__c
            FROM Product2
            WHERE Id = :ids.product2Id
        ];

        System.assertEquals(
            false,
            product.RES_Is_In_Soft_Hold_Extension__c,
            'Soft Hold Extension flag should be false.'
        );

        System.assertEquals(
            'Available',
            product.RES_Unit_Status__c,
            'Product should become Available when the extension is expired.'
        );
    }


    /**
     * Reject:
     *
     * Soft Hold Until is expired.
     *
     * Expected:
     * - Extension flag = false
     * - Unit Status = Available
     */
    @IsTest(SeeAllData=true)
    static void testRejectExpiredSoftHold() {
        TestDataIds ids = createTestData();

        Quote quote = [
            SELECT Id,
                    RES_Extend_Soft_Hold_By_Hours__c
            FROM Quote
            WHERE Id = :ids.quote3Id
        ];

        insertServiceChargeRateOverride(ids.product3Id);

        RES_SoftHoldPostApprovalActions.input inputObj =
            new RES_SoftHoldPostApprovalActions.input();

        inputObj.quote = quote;
        inputObj.action = 'Reject';

        Test.startTest();

        RES_SoftHoldPostApprovalActions.executeSoftHoldPostApprovalActions(
            new List<RES_SoftHoldPostApprovalActions.input>{
                inputObj
            }
        );

        Test.stopTest();

        Product2 product = [
            SELECT Id,
                    RES_Unit_Status__c,
                    RES_Is_In_Soft_Hold_Extension__c
            FROM Product2
            WHERE Id = :ids.product3Id
        ];

        System.assertEquals(
            false,
            product.RES_Is_In_Soft_Hold_Extension__c,
            'Soft Hold Extension flag should be false.'
        );

        System.assertEquals(
            'Available',
            product.RES_Unit_Status__c,
            'Expired rejected soft hold should become Available.'
        );
    }


    /**
     * Reject:
     *
     * Soft Hold Until is still in the future.
     *
     * Expected:
     * - Extension flag = false
     * - Unit Status should remain unchanged.
     */
    @IsTest
    static void testRejectActiveSoftHold() {
        createTestData();

        Account acc = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Id standardPricebookId = Test.getStandardPricebookId();

        Product2 product = new Product2(
            Name = 'Unit A104',
            IsActive = true,
            RES_Unit_Status__c = 'Soft Hold',
            RES_Soft_Hold_Until__c = System.now().addHours(5),
            RES_Is_In_Soft_Hold_Extension__c = true
        );
        insert product;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = product.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity 4',
            AccountId = acc.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = standardPricebookId
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'Test Quote 4',
            OpportunityId = opp.Id,
            Pricebook2Id = standardPricebookId,
            RES_Extend_Soft_Hold_By_Hours__c = 8
        );
        insert quote;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = quote.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert qli;

        RES_SoftHoldPostApprovalActions.input inputObj =
            new RES_SoftHoldPostApprovalActions.input();

        inputObj.quote = quote;
        inputObj.action = 'Reject';

        Test.startTest();

        RES_SoftHoldPostApprovalActions.executeSoftHoldPostApprovalActions(
            new List<RES_SoftHoldPostApprovalActions.input>{
                inputObj
            }
        );

        Test.stopTest();

        Product2 productAfter = [
            SELECT Id,
                    RES_Unit_Status__c,
                    RES_Is_In_Soft_Hold_Extension__c
            FROM Product2
            WHERE Id = :product.Id
        ];

        System.assertEquals(
            false,
            productAfter.RES_Is_In_Soft_Hold_Extension__c,
            'Soft Hold Extension flag should be false.'
        );

        System.assertEquals(
            'Soft Hold',
            productAfter.RES_Unit_Status__c,
            'Product should remain in Soft Hold because the hold has not expired.'
        );
    }


    /**
     * Action other than Approve / Reject.
     *
     * Expected:
     * No Product updates.
     */
    @IsTest
    static void testInvalidAction() {
        createTestData();

        Quote quote = [
            SELECT Id,
                    RES_Extend_Soft_Hold_By_Hours__c
            FROM Quote
            WHERE Name = 'Test Quote 1'
            LIMIT 1
        ];

        Product2 productBefore = [
            SELECT Id,
                    RES_Unit_Status__c,
                    RES_Is_In_Soft_Hold_Extension__c
            FROM Product2
            WHERE Name = 'Unit A101'
            LIMIT 1
        ];

        RES_SoftHoldPostApprovalActions.input inputObj =
            new RES_SoftHoldPostApprovalActions.input();

        inputObj.quote = quote;
        inputObj.action = 'SomethingElse';

        Test.startTest();

        RES_SoftHoldPostApprovalActions.executeSoftHoldPostApprovalActions(
            new List<RES_SoftHoldPostApprovalActions.input>{
                inputObj
            }
        );

        Test.stopTest();

        Product2 productAfter = [
            SELECT Id,
                   RES_Unit_Status__c,
                   RES_Is_In_Soft_Hold_Extension__c
            FROM Product2
            WHERE Id = :productBefore.Id
        ];

        System.assertEquals(
            productBefore.RES_Unit_Status__c,
            productAfter.RES_Unit_Status__c,
            'Product status should not change for an unsupported action.'
        );

        System.assertEquals(
            productBefore.RES_Is_In_Soft_Hold_Extension__c,
            productAfter.RES_Is_In_Soft_Hold_Extension__c,
            'Extension flag should not change for an unsupported action.'
        );
    }


    /**
     * Bulk test.
     *
     * Tests multiple invocable inputs in a single invocation.
     */
    @IsTest
    static void testBulkProcessing() {
        createTestData();

        List<Quote> quotes = [
            SELECT Id,
                    RES_Extend_Soft_Hold_By_Hours__c
            FROM Quote
            WHERE Name IN (
                'Test Quote 1',
                'Test Quote 3'
            )
        ];

        List<RES_SoftHoldPostApprovalActions.input> inputs =
            new List<RES_SoftHoldPostApprovalActions.input>();

        for (Quote quote : quotes) {

            RES_SoftHoldPostApprovalActions.input inputObj =
                new RES_SoftHoldPostApprovalActions.input();

            inputObj.quote = quote;

            if (quote.Id == [
                SELECT Id
                FROM Quote
                WHERE Name = 'Test Quote 1'
                LIMIT 1
            ].Id) {
                inputObj.action = 'Approve';
            }
            else {
                inputObj.action = 'Reject';
            }

            inputs.add(inputObj);
        }

        Test.startTest();

        RES_SoftHoldPostApprovalActions.executeSoftHoldPostApprovalActions(
            inputs
        );

        Test.stopTest();

        System.assertEquals(
            2,
            inputs.size(),
            'Two inputs should have been processed.'
        );
    }
}
