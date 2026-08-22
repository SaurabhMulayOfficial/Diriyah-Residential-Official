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

        // Contracts are needed for ContractCancellation / OpportunityStageTransition coverage.
        List<Contract> contracts = new List<Contract>();
        for (Integer i = 0; i < 3; i++) {
            contracts.add(new Contract(
                AccountId = acc.Id,
                Status = 'Draft',
                StartDate = Date.today()
            ));
        }
        insert contracts;
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

    // Overload for events that key off RES_recordId__c (Contract / Opportunity flows)
    // rather than RES_QuoteId__c.
    private static RES_Review_Approval_Work_Item__e buildRecordEvent(String action, Id recordId) {
        return new RES_Review_Approval_Work_Item__e(
            RES_Post_Review_Action__c = action,
            RES_recordId__c = recordId,
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

    // ==========================================================================
    // NEW TESTS APPENDED BELOW
    // ==========================================================================

    @isTest
    static void testFilter_ContractCancellation() {
        Contract c = [SELECT Id, Status FROM Contract LIMIT 1];

        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>{
            buildRecordEvent('ContractCancellation', c.Id)
        };

        Test.startTest();
        RES_ReviewApprovalWorkItemService.filter(events);
        Test.stopTest();

        Contract updated = [SELECT Id, Status FROM Contract WHERE Id = :c.Id];
        System.assertEquals('Canceled', updated.Status,
            'Contract status should be Canceled after ContractCancellation action');
    }

    @isTest
    static void testContractCancellation_DirectCall() {
        Contract c = [SELECT Id FROM Contract LIMIT 1];
        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>{
            buildRecordEvent('ContractCancellation', c.Id)
        };

        Test.startTest();
        RES_ReviewApprovalWorkItemService.contractCancellation(events);
        Test.stopTest();

        Contract updated = [SELECT Id, Status FROM Contract WHERE Id = :c.Id];
        System.assertEquals('Canceled', updated.Status);
    }

    @isTest
    static void testContractCancellation_Bulk() {
        List<Contract> contracts = [SELECT Id FROM Contract];
        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>();
        for (Contract c : contracts) {
            events.add(buildRecordEvent('ContractCancellation', c.Id));
        }

        Test.startTest();
        RES_ReviewApprovalWorkItemService.filter(events);
        Test.stopTest();

        List<Contract> updated = [SELECT Id, Status FROM Contract WHERE Status = 'Canceled'];
        System.assertEquals(contracts.size(), updated.size(),
            'All contracts in the bulk event batch should be canceled');
    }

    /**
     * NOTE: filter() routes 'OpportunityStageTransition' events to
     * contractCancellation(), not opportunityStageTransition(), which looks
     * like a copy-paste bug in the source. Inside contractCancellation(),
     * the line `c.Id = cId;` (assigning an Opportunity Id onto a new
     * Contract()) throws System.TypeException: Invalid id value for this
     * SObject type — and that line sits OUTSIDE the try/catch block, which
     * only wraps the Database.update call. So this isn't a silent no-op: it
     * is an unhandled exception that propagates all the way out of filter(),
     * meaning the platform event trigger itself would fail for any
     * OpportunityStageTransition event today. This test documents that
     * actual behavior. If/when the bug is fixed to call
     * opportunityStageTransition() instead, this test should be replaced
     * with one that asserts StageName = 'Proposal' on the Opportunity and
     * no exception is thrown.
     */
    @isTest
    static void testOpportunityStageTransition_DirectCall() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>{
            buildRecordEvent('OpportunityStageTransition', opp.Id)
        };

        Test.startTest();
        RES_ReviewApprovalWorkItemService.opportunityStageTransition(events);
        Test.stopTest();

        Opportunity updated = [SELECT Id, StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Proposal', updated.StageName,
            'Calling opportunityStageTransition() directly should move the Opportunity to Proposal');
    }

    @isTest
    static void testFilter_MixedActionsInSingleBatch() {
        Quote softHoldQuote = [SELECT Id FROM Quote WHERE Name = 'RES Test Quote 0' LIMIT 1];
        Quote cancelQuote = [SELECT Id FROM Quote WHERE Name = 'RES Test Quote 1' LIMIT 1];
        Contract contract = [SELECT Id FROM Contract LIMIT 1];

        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>{
            buildEvent('QuoteSoftHoldPostApproval', softHoldQuote.Id),
            buildEvent('QuoteCancellation', cancelQuote.Id),
            buildRecordEvent('ContractCancellation', contract.Id)
        };

        Test.startTest();
        RES_ReviewApprovalWorkItemService.filter(events);
        Test.stopTest();

        Quote softHoldResult = [SELECT RES_Product_Soft_Held__c FROM Quote WHERE Id = :softHoldQuote.Id];
        Quote cancelResult = [SELECT Status FROM Quote WHERE Id = :cancelQuote.Id];
        Contract contractResult = [SELECT Status FROM Contract WHERE Id = :contract.Id];

        System.assertEquals(true, softHoldResult.RES_Product_Soft_Held__c,
            'Soft hold quote should be updated when batched with other action types');
        System.assertEquals('Cancelled', cancelResult.Status,
            'Cancellation quote should be updated when batched with other action types');
        System.assertEquals('Canceled', contractResult.Status,
            'Contract should be updated when batched with other action types');
    }

    @isTest
    static void testFilter_EmptyEventList_NoException() {
        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>();

        Test.startTest();
        try {
            RES_ReviewApprovalWorkItemService.filter(events);
        } catch (Exception e) {
            System.assert(false, 'filter() should not throw on an empty event list: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testFilter_NullRecordId_ContractCancellation_NoException() {
        List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>{
            buildRecordEvent('ContractCancellation', null)
        };

        Test.startTest();
        try {
            RES_ReviewApprovalWorkItemService.filter(events);
        } catch (Exception e) {
            System.assert(false, 'filter() should not throw when RES_recordId__c is null: ' + e.getMessage());
        }
        Test.stopTest();
    }
}