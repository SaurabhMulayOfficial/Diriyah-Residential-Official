/**
 * ==============================================================================
 * Class Name    : RES_QuoteCancellationServiceTest
 * Description   : Test coverage for RES_QuoteCancellationService.cancelQuotations.
 *
 * NOTE ON APPROVAL WORK ITEMS:
 * Just like RES_ReviewApprovalWorkItemServiceTest, we cannot insert a real
 * ApprovalWorkItem in a test context without submitting a record through a
 * live approval process. These tests therefore exercise the "no pending
 * approval work items" branch (pendingItems is empty), which is the code
 * path that directly updates Quote/Contract/Opportunity and is fully
 * testable without org-specific approval process configuration.
 * ==============================================================================
 */
@isTest
private class RES_QuoteCancellationServiceTest {

    // Holds the Ids setupData() creates, so callers never have to re-query generic fixture
    // Names - under SeeAllData=true those aren't guaranteed unique against real org data,
    // making a LIMIT 1 re-query non-deterministic.
    private class TestDataIds {
        Id quoteId;
        Id contractId;
        Id opportunityId;
        Id productId;
    }

    /** Not @TestSetup: testCancelQuotations_ProductUnitStatus_NotPersisted needs SeeAllData=true to safely reuse the org's real Service Charge Rate AttributeDefinition, and a class can't mix @TestSetup with any SeeAllData=true method. Every test method calls this explicitly instead. */
    static TestDataIds setupData() {
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        config.RES_Triggers_Off__c = true;
        upsert config;

        Account acc = new Account(Name = 'RES QCS Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'RES QCS Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Contract con = new Contract(
            AccountId = acc.Id,
            Status = 'Draft',
            StartDate = Date.today()
        );
        insert con;

        Quote q = new Quote(
            Name = 'RES QCS Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = resolvePricebookId()
        );
        insert q;

        opp.SyncedQuoteId = q.Id;
        update opp;

        Product2 prod = new Product2(
            Name = 'RES QCS Test Unit',
            IsActive = true,
            RES_Unit_Status__c = 'Soft Hold',
            RES_Reserved_By_Quote__c = q.Id
        );
        insert prod;

        PricebookEntry pbe = insertTargetPricebookEntry(prod.Id, 100);

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert qli;

        TestDataIds ids = new TestDataIds();
        ids.quoteId = q.Id;
        ids.contractId = con.Id;
        ids.opportunityId = opp.Id;
        ids.productId = prod.Id;
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
                Name = 'RES Test QCS SC Rate Attribute', Label = 'RES Test QCS SC Rate Attribute',
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
                Code = 'RES_TEST_QCS_' + String.valueOf(Crypto.getRandomInteger()).right(8),
                Name = 'RES Test QCS Classification',
                Status = 'Active'
            );
            insert classification;
            classificationAttr = new ProductClassificationAttr(
                Name = 'RES Test QCS Classification Attr',
                ProductClassificationId = classification.Id,
                AttributeDefinitionId = scRateAttr.Id
            );
            insert classificationAttr;
        }

        // Product2.BasedOnId must match the ProductClassificationAttr's own classification
        update new Product2(Id = productId, BasedOnId = classificationAttr.ProductClassificationId);

        insert new ProductAttributeDefinition(
            Name = 'RES Test QCS SC Rate Override',
            ProductClassificationAttributeId = classificationAttr.Id,
            Product2Id = productId,
            AttributeDefinitionId = scRateAttr.Id,
            DefaultValue = '120'
        );
    }

    @isTest
    static void testCancelQuotations_NoPendingApprovals_UpdatesQuoteContractOpportunity() {
        TestDataIds ids = setupData();

        RES_QuoteCancellationService.input in1 = new RES_QuoteCancellationService.input();
        in1.quoteInstance = new Quote(Id = ids.quoteId, ContractId = ids.contractId, OpportunityId = ids.opportunityId, RES_Cancellation_Reason__c = 'Test cancellation reason');

        Test.startTest();
        RES_QuoteCancellationService.cancelQuotations(new List<RES_QuoteCancellationService.input>{ in1 });
        Test.stopTest();

        Quote updatedQuote = [SELECT Id, Status, RES_Cancellation_Reason__c FROM Quote WHERE Id = :ids.quoteId];
        Contract updatedContract = [SELECT Id, Status FROM Contract WHERE Id = :ids.contractId];
        Opportunity updatedOpp = [SELECT Id, StageName FROM Opportunity WHERE Id = :ids.opportunityId];

        System.assertEquals('Cancelled', updatedQuote.Status, 'Quote should be cancelled');
        System.assertEquals('Test cancellation reason', updatedQuote.RES_Cancellation_Reason__c, 'Cancellation reason should be persisted on the Quote');
        System.assertEquals('Canceled', updatedContract.Status, 'Related Contract should be canceled');
        System.assertEquals('Unit Selected', updatedOpp.StageName, 'Related Opportunity should move to Proposal stage');
    }

    @isTest
    static void testCancelQuotations_QuoteOnly_BulkSafe() {
        TestDataIds ids = setupData();
        List<RES_QuoteCancellationService.input> inputs = new List<RES_QuoteCancellationService.input>();
        RES_QuoteCancellationService.input in1 = new RES_QuoteCancellationService.input();
        in1.quoteInstance = new Quote(Id = ids.quoteId, RES_Cancellation_Reason__c = 'Test cancellation reason'); // ContractId/OpportunityId intentionally null
        inputs.add(in1);


        Test.startTest();
        try {
            RES_QuoteCancellationService.cancelQuotations(inputs);
        } catch (Exception e) {
            System.assert(false, 'cancelQuotations should not throw for a Quote-only input: ' + e.getMessage());
        }
        Test.stopTest();

        Quote updatedQuote = [SELECT Id, Status FROM Quote WHERE Id = :ids.quoteId];
        System.assertEquals('Cancelled', updatedQuote.Status, 'Quote should be cancelled even with no related Contract/Opportunity');
    }

    @isTest(SeeAllData=true)
    static void testCancelQuotations_ProductUnitStatus_NotPersisted() {
        TestDataIds ids = setupData();
        insertServiceChargeRateOverride(ids.productId);

        RES_QuoteCancellationService.input in1 = new RES_QuoteCancellationService.input();
        in1.quoteInstance = new Quote(Id = ids.quoteId, RES_Cancellation_Reason__c = 'Test cancellation reason');

        Test.startTest();
        RES_QuoteCancellationService.cancelQuotations(new List<RES_QuoteCancellationService.input>{ in1 });
        Test.stopTest();

        Product2 unchangedProduct = [SELECT Id, RES_Unit_Status__c FROM Product2 WHERE Id = :ids.productId];
        System.assertEquals('Available', unchangedProduct.RES_Unit_Status__c, 'Product Marked as Available');
    }
}
