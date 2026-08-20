/**
 * ==============================================================================
 * Class Name    : RES_ReviewApprovalWorkItemServiceTest
 * Description   : Test coverage for RES_ReviewApprovalWorkItemService.
 *
 * NOTE ON APPROVAL WORK ITEMS:
 * A real ProcessInstanceWorkItem can only be created by submitting a record
 * through a live approval process, so we cannot insert one directly in a test.
 * Instead we pass a syntactically valid but non-existent Id into
 * RES_Approval_Work_Item_Id__c. RES_ApprovalWorkItemManagement.processWorkItems
 * will fail to find it, but that failure is already caught and swallowed by
 * updateApprovalWorkItems(), so the rest of the flow (the Quote update) is
 * still fully exercised and asserted below.
 * ==============================================================================
 */
@isTest
private class RES_ReviewApprovalWorkItemServiceTest {

    // Well-formed (18 char, valid base62) but non-existent Id.
    private static final String FAKE_WORK_ITEM_ID = '04g000000000AAAAAA';

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'RES Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'RES Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        List<Quote> quotes = new List<Quote>();
        for (Integer i = 0; i < 5; i++) {
            quotes.add(new Quote(
                Name = 'RES Test Quote ' + i,
                OpportunityId = opp.Id,
                Pricebook2Id = Test.getStandardPricebookId()
            ));
        }
        insert quotes;
    }

    private static RES_Review_Approval_Work_Item__e buildEvent(String action, Id quoteId) {
        return new RES_Review_Approval_Work_Item__e(
            RES_Post_Review_Action__c = action,
            RES_QuoteId__c = quoteId,
            RES_Approval_Decision__c = 'Approve',
            RES_Approval_Comments__c = 'Approved via test',
            RES_Approval_Work_Item_Id__c = FAKE_WORK_ITEM_ID
        );
    }

    @isTest
    static void testFilter_QuoteSoftHoldPostApproval() {
        Quote q = [SELECT Id, RES_Product_Soft_Held__c FROM Quote LIMIT 1];

        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>{
            buildEvent('QuoteSoftHoldPostApproval', q.Id)
        };

        Test.startTest();
        RES_ReviewApprovalWorkItemService.filter(events);
        Test.stopTest();

        Quote updated = [SELECT Id, RES_Product_Soft_Held__c FROM Quote WHERE Id = :q.Id];
        System.assertEquals(true, updated.RES_Product_Soft_Held__c,
            'Quote should be marked as soft held after QuoteSoftHoldPostApproval');
    }

    @isTest
    static void testFilter_QuoteCancellation() {
        Quote q = [SELECT Id, Status FROM Quote LIMIT 1];

        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>{
            buildEvent('QuoteCancellation', q.Id)
        };

        Test.startTest();
        RES_ReviewApprovalWorkItemService.filter(events);
        Test.stopTest();

        Quote updated = [SELECT Id, Status FROM Quote WHERE Id = :q.Id];
        System.assertEquals('Cancelled', updated.Status,
            'Quote status should be Cancelled after QuoteCancellation action');
    }

    @isTest
    static void testFilter_BulkEvents_SoftHold() {
        List<Quote> quotes = [SELECT Id FROM Quote];
        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>();
        for (Quote q : quotes) {
            events.add(buildEvent('QuoteSoftHoldPostApproval', q.Id));
        }

        Test.startTest();
        RES_ReviewApprovalWorkItemService.filter(events);
        Test.stopTest();

        List<Quote> updated = [SELECT Id, RES_Product_Soft_Held__c FROM Quote WHERE RES_Product_Soft_Held__c = true];
        System.assertEquals(quotes.size(), updated.size(),
            'All quotes in the bulk event batch should be updated');
    }

    @isTest
    static void testFilter_UnrecognizedAction_NoQuoteUpdate() {
        Quote q = [SELECT Id, Status, RES_Product_Soft_Held__c FROM Quote LIMIT 1];

        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>{
            buildEvent('SomeOtherAction', q.Id)
        };

        Test.startTest();
        RES_ReviewApprovalWorkItemService.filter(events);
        Test.stopTest();

        Quote unchanged = [SELECT Id, Status, RES_Product_Soft_Held__c FROM Quote WHERE Id = :q.Id];
        System.assertEquals(q.Status, unchanged.Status, 'Status should be unaffected for an unrecognized action');
        System.assertEquals(false, unchanged.RES_Product_Soft_Held__c, 'Soft hold flag should be unaffected');
    }

    @isTest
    static void testFilter_NullQuoteId_NoException() {
        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>{
            buildEvent('QuoteSoftHoldPostApproval', null)
        };

        Test.startTest();
        try {
            RES_ReviewApprovalWorkItemService.filter(events);
        } catch (Exception e) {
            System.assert(false, 'filter() should not throw when RES_QuoteId__c is null: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testRunQuotePostApprovals_DirectCall() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>{
            buildEvent('QuoteSoftHoldPostApproval', q.Id)
        };

        Test.startTest();
        RES_ReviewApprovalWorkItemService.runQuotePostApprovals(events);
        Test.stopTest();

        Quote updated = [SELECT Id, RES_Product_Soft_Held__c FROM Quote WHERE Id = :q.Id];
        System.assertEquals(true, updated.RES_Product_Soft_Held__c);
    }

    @isTest
    static void testQuoteCancellation_DirectCall() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>{
            buildEvent('QuoteCancellation', q.Id)
        };

        Test.startTest();
        RES_ReviewApprovalWorkItemService.quoteCancellation(events);
        Test.stopTest();

        Quote updated = [SELECT Id, Status FROM Quote WHERE Id = :q.Id];
        System.assertEquals('Cancelled', updated.Status);
    }

    @isTest
    static void testUpdateApprovalWorkItems_ExceptionSwallowed() {
        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>{
            buildEvent('QuoteSoftHoldPostApproval', null)
        };

        Test.startTest();
        try {
            RES_ReviewApprovalWorkItemService.updateApprovalWorkItems(events);
        } catch (Exception e) {
            System.assert(false, 'Failures from RES_ApprovalWorkItemManagement should be caught internally: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testTrigger_EventBusPublish() {
        RES_Review_Approval_Work_Item__e evt = new RES_Review_Approval_Work_Item__e(
            RES_Post_Review_Action__c = 'QuoteSoftHoldPostApproval',
            RES_QuoteId__c = null,
            RES_Approval_Decision__c = 'Approve',
            RES_Approval_Comments__c = 'Approved via test',
            RES_Approval_Work_Item_Id__c = '04g000000000AAAAAA'
        );

        Test.startTest();
        EventBus.publish(evt);
        Test.stopTest();
    }
}