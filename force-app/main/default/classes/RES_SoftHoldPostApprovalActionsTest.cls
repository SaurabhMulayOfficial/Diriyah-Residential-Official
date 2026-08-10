@IsTest
private class RES_SoftHoldPostApprovalActionsTest {

    @TestSetup
    static void createTestData() {

        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;

        Id standardPricebookId = Test.getStandardPricebookId();

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

        pbes.add(new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = product1.Id,
            UnitPrice = 100,
            IsActive = true
        ));

        pbes.add(new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = product2.Id,
            UnitPrice = 100,
            IsActive = true
        ));

        pbes.add(new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = product3.Id,
            UnitPrice = 100,
            IsActive = true
        ));

        insert pbes;

        // Opportunity 1
        Opportunity opp1 = new Opportunity(
            Name = 'Test Opportunity 1',
            AccountId = acc.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = standardPricebookId
        );
        insert opp1;

        // Opportunity 2
        Opportunity opp2 = new Opportunity(
            Name = 'Test Opportunity 2',
            AccountId = acc.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = standardPricebookId
        );
        insert opp2;

        // Opportunity 3
        Opportunity opp3 = new Opportunity(
            Name = 'Test Opportunity 3',
            AccountId = acc.Id,
            StageName = 'Proposal',
            CloseDate = Date.today(),
            Pricebook2Id = standardPricebookId
        );
        insert opp3;

        // Quotes
        Quote quote1 = new Quote(
            Name = 'Test Quote 1',
            OpportunityId = opp1.Id,
            Pricebook2Id = standardPricebookId,
            RES_Extend_Soft_Hold_By_Hours__c = 8
        );

        Quote quote2 = new Quote(
            Name = 'Test Quote 2',
            OpportunityId = opp2.Id,
            Pricebook2Id = standardPricebookId,
            RES_Extend_Soft_Hold_By_Hours__c = 8
        );

        Quote quote3 = new Quote(
            Name = 'Test Quote 3',
            OpportunityId = opp3.Id,
            Pricebook2Id = standardPricebookId,
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
    @IsTest
    static void testApproveExpiredSoftHold() {

        Quote quote = [
            SELECT Id,
                    RES_Extend_Soft_Hold_By_Hours__c
            FROM Quote
            WHERE Name = 'Test Quote 2'
            LIMIT 1
        ];

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
            WHERE Name = 'Unit A102'
            LIMIT 1
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
    @IsTest
    static void testRejectExpiredSoftHold() {

        Quote quote = [
            SELECT Id,
                    RES_Extend_Soft_Hold_By_Hours__c
            FROM Quote
            WHERE Name = 'Test Quote 3'
            LIMIT 1
        ];

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
            WHERE Name = 'Unit A103'
            LIMIT 1
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
