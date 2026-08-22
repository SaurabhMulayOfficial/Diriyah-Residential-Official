@IsTest
private class RES_QuoteDiscountRejectionCounterTest {
    @TestSetup
    static void createData() {
        insert new RES_Config_Switch__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            RES_Validation_Rules_Off__c = true
        );

        Account accountRecord = new Account(Name = 'Discount Rejection Counter Account');
        insert accountRecord;
        Opportunity opportunityRecord = new Opportunity(
            Name = 'Discount Rejection Counter Opportunity',
            AccountId = accountRecord.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Prospecting',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert opportunityRecord;

        Quote quoteWithThreeRejections = new Quote(
            Name = 'Three rejections',
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = 'Draft'
        );
        Quote quoteWithFourRejections = new Quote(
            Name = 'Four rejections',
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = 'Draft'
        );
        Quote quoteWithoutRejections = new Quote(
            Name = 'No rejections',
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = 'Draft'
        );
        insert new List<Quote>{ quoteWithThreeRejections, quoteWithFourRejections, quoteWithoutRejections };

        List<RES_Discount_Audit_Log__c> logs = new List<RES_Discount_Audit_Log__c>();
        for (Integer index = 0; index < 3; index++) {
            logs.add(rejectionLog(quoteWithThreeRejections.Id));
        }
        for (Integer index = 0; index < 4; index++) {
            logs.add(rejectionLog(quoteWithFourRejections.Id));
        }
        logs.add(new RES_Discount_Audit_Log__c(
            RES_Quote__c = quoteWithThreeRejections.Id,
            RES_Entry_Type__c = 'Approval',
            RES_Outcome__c = 'Approved',
            RES_Discount_Requested__c = 10
        ));
        insert logs;
    }

    @IsTest
    static void countsOnlyRejectedDiscountAuditEntries() {
        Map<String, Id> quoteIdsByName = new Map<String, Id>();
        for (Quote quoteRecord : [SELECT Id, Name FROM Quote]) {
            quoteIdsByName.put(quoteRecord.Name, quoteRecord.Id);
        }
        List<RES_QuoteDiscountApprovalService.Input> inputs = new List<RES_QuoteDiscountApprovalService.Input>{
            requestFor(quoteIdsByName.get('Three rejections')),
            requestFor(quoteIdsByName.get('Four rejections')),
            requestFor(quoteIdsByName.get('No rejections'))
        };

        Test.startTest();
        List<RES_QuoteDiscountApprovalService.Output> outputs =
            RES_QuoteDiscountApprovalService.getRejectionCounts(inputs);
        Test.stopTest();

        System.assertEquals(3, outputs[0].rejectionCount);
        System.assertEquals(4, outputs[1].rejectionCount);
        System.assertEquals(0, outputs[2].rejectionCount);
    }

    private static RES_Discount_Audit_Log__c rejectionLog(Id quoteId) {
        return new RES_Discount_Audit_Log__c(
            RES_Quote__c = quoteId,
            RES_Entry_Type__c = 'Rejection',
            RES_Outcome__c = 'Rejected',
            RES_Discount_Requested__c = 10
        );
    }

    private static RES_QuoteDiscountApprovalService.Input requestFor(Id quoteId) {
        RES_QuoteDiscountApprovalService.Input request =
            new RES_QuoteDiscountApprovalService.Input();
        request.quoteId = quoteId;
        return request;
    }
}
