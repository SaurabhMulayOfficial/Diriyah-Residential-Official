@isTest
private class RES_QuoteApprovalWorkItemServiceTest {
    @isTest
    static void testGetPriorRejectionCountsWithNullOrEmptyInput() {
        System.assertEquals(0, RES_QuoteApprovalWorkItemService.getPriorRejectionCounts(null).size());
        System.assertEquals(0, RES_QuoteApprovalWorkItemService.getPriorRejectionCounts(new Set<Id>()).size());
    }

    @isTest
    static void testGetPriorRejectionCountsDefaultsToZeroWhenNoWorkItems() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        Opportunity opp = new Opportunity(Name = 'Test Opp', StageName = 'Prospecting', CloseDate = Date.today().addDays(30), AccountId = acc.Id);
        insert opp;
        Quote q = new Quote(Name = 'Test Quote', OpportunityId = opp.Id);
        insert q;

        Map<Id, Integer> counts = RES_QuoteApprovalWorkItemService.getPriorRejectionCounts(new Set<Id>{ q.Id });

        System.assertEquals(1, counts.size());
        System.assertEquals(0, counts.get(q.Id));
    }

    @isTest
    static void testGetRejectionCountsInvocableBulkAndNullSafe() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        Opportunity opp = new Opportunity(Name = 'Test Opp', StageName = 'Prospecting', CloseDate = Date.today().addDays(30), AccountId = acc.Id);
        insert opp;
        Quote q1 = new Quote(Name = 'Test Quote 1', OpportunityId = opp.Id);
        Quote q2 = new Quote(Name = 'Test Quote 2', OpportunityId = opp.Id);
        insert new List<Quote>{ q1, q2 };

        RES_QuoteApprovalWorkItemService.Input input1 = new RES_QuoteApprovalWorkItemService.Input();
        input1.quoteId = q1.Id;
        RES_QuoteApprovalWorkItemService.Input input2 = new RES_QuoteApprovalWorkItemService.Input();
        input2.quoteId = q2.Id;
        RES_QuoteApprovalWorkItemService.Input inputNull = new RES_QuoteApprovalWorkItemService.Input();

        List<RES_QuoteApprovalWorkItemService.Output> outputs = RES_QuoteApprovalWorkItemService.getRejectionCounts(
            new List<RES_QuoteApprovalWorkItemService.Input>{ input1, input2, inputNull }
        );

        System.assertEquals(3, outputs.size());
        System.assertEquals(0, outputs[0].rejectionCount);
        System.assertEquals(0, outputs[1].rejectionCount);
        System.assertEquals(0, outputs[2].rejectionCount);
    }
}
