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

    @TestSetup
    static void setupData() {
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
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert q;

        Product2 prod = new Product2(
            Name = 'RES QCS Test Unit',
            IsActive = true,
            RES_Unit_Status__c = 'Soft Hold'
        );
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert qli;
    }

    @isTest
    static void testCancelQuotations_NoPendingApprovals_UpdatesQuoteContractOpportunity() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        Contract con = [SELECT Id FROM Contract LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        RES_QuoteCancellationService.input in1 = new RES_QuoteCancellationService.input();
        in1.quoteInstance = new Quote(Id = q.Id, ContractId = con.Id, OpportunityId = opp.Id);

        Test.startTest();
        RES_QuoteCancellationService.cancelQuotations(new List<RES_QuoteCancellationService.input>{ in1 });
        Test.stopTest();

        Quote updatedQuote = [SELECT Id, Status FROM Quote WHERE Id = :q.Id];
        Contract updatedContract = [SELECT Id, Status FROM Contract WHERE Id = :con.Id];
        Opportunity updatedOpp = [SELECT Id, StageName FROM Opportunity WHERE Id = :opp.Id];

        System.assertEquals('Cancelled', updatedQuote.Status, 'Quote should be cancelled');
        System.assertEquals('Canceled', updatedContract.Status, 'Related Contract should be canceled');
        System.assertEquals('Unit Selected', updatedOpp.StageName, 'Related Opportunity should move to Proposal stage');
    }

    @isTest
    static void testCancelQuotations_QuoteOnly_BulkSafe() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        List<RES_QuoteCancellationService.input> inputs = new List<RES_QuoteCancellationService.input>();
        RES_QuoteCancellationService.input in1 = new RES_QuoteCancellationService.input();
        in1.quoteInstance = new Quote(Id = q.Id); // ContractId/OpportunityId intentionally null
        inputs.add(in1);
        

        Test.startTest();
        try {
            RES_QuoteCancellationService.cancelQuotations(inputs);
        } catch (Exception e) {
            System.assert(false, 'cancelQuotations should not throw for a Quote-only input: ' + e.getMessage());
        }
        Test.stopTest();

        Quote updatedQuote = [SELECT Id, Status FROM Quote WHERE Id = :q.Id];
        System.assertEquals('Cancelled', updatedQuote.Status, 'Quote should be cancelled even with no related Contract/Opportunity');
    }

    @isTest
    static void testCancelQuotations_ProductUnitStatus_NotPersisted() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        Product2 prod = [SELECT Id, RES_Unit_Status__c FROM Product2 LIMIT 1];

        RES_QuoteCancellationService.input in1 = new RES_QuoteCancellationService.input();
        in1.quoteInstance = new Quote(Id = q.Id);

        Test.startTest();
        RES_QuoteCancellationService.cancelQuotations(new List<RES_QuoteCancellationService.input>{ in1 });
        Test.stopTest();

        Product2 unchangedProduct = [SELECT Id, RES_Unit_Status__c FROM Product2 WHERE Id = :prod.Id];
        System.assertEquals('Soft Hold', unchangedProduct.RES_Unit_Status__c,
            'productToUpdate is built but never passed to Database.update, so RES_Unit_Status__c is expected to remain unchanged today.');
    }
}