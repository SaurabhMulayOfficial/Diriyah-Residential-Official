@isTest
private class RES_UnitDraftCancellationServiceTest {

    private static final String UNIT_NAME = 'RES UDC Test Unit';
    private static final String NON_BUNDLE_UNIT_NAME = 'RES UDC Test Non Bundle Unit';

    private static Id residentialSalesRecordTypeId() {
        return Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName().get('RES_Residential_Sales').getRecordTypeId();
    }

    @TestSetup
    static void setupData() {
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        config.RES_Triggers_Off__c = true;
        upsert config;

        Account acc = new Account(Name = 'RES UDC Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'RES UDC Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Contract quoteContract = new Contract(AccountId = acc.Id, Status = 'Draft', StartDate = Date.today(), Description = 'QUOTE');
        Contract cipContract = new Contract(AccountId = acc.Id, Status = 'Draft', StartDate = Date.today(), Description = 'CIP');
        insert new List<Contract>{ quoteContract, cipContract };

        Quote q = new Quote(
            Name = 'RES UDC Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            ContractId = quoteContract.Id
        );
        insert q;

        opp.SyncedQuoteId = q.Id;
        update opp;

        Product2 unit = new Product2(
            Name = UNIT_NAME,
            ProductCode = 'RES-UDC-TEST-UNIT-001',
            IsActive = true,
            RecordTypeId = residentialSalesRecordTypeId(),
            Type = 'Bundle',
            RES_Unit_Status__c = 'Soft Hold',
            RES_Reserved_By_Quote__c = q.Id,
            RES_Soft_Hold_Start__c = System.now(),
            RES_Soft_Hold_Until__c = System.now().addDays(1)
        );
        insert unit;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(), Product2Id = unit.Id, UnitPrice = 100, IsActive = true
        );
        insert pbe;

        insert new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 100);
        insert new ContractItemPrice(ContractId = cipContract.Id, ItemId = unit.Id, RES_Product__c = unit.Id, RES_CIP_Type__c = 'Unit', Price = 100);

        // Type is create-only, so the non-bundle case gets its own unit and quote
        Quote nonBundleQuote = new Quote(Name = 'RES UDC Non Bundle Quote', OpportunityId = opp.Id, Pricebook2Id = Test.getStandardPricebookId());
        insert nonBundleQuote;
        Product2 nonBundleUnit = new Product2(
            Name = NON_BUNDLE_UNIT_NAME,
            ProductCode = 'RES-UDC-TEST-UNIT-002',
            IsActive = true,
            RecordTypeId = residentialSalesRecordTypeId(),
            RES_Unit_Status__c = 'Soft Hold'
        );
        insert nonBundleUnit;
        PricebookEntry nonBundlePbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(), Product2Id = nonBundleUnit.Id, UnitPrice = 100, IsActive = true
        );
        insert nonBundlePbe;
        insert new QuoteLineItem(QuoteId = nonBundleQuote.Id, PricebookEntryId = nonBundlePbe.Id, Quantity = 1, UnitPrice = 100);
    }

    private static Id getUnitId(String name) {
        return [SELECT Id FROM Product2 WHERE Name = :name LIMIT 1].Id;
    }

    private static void moveUnitToDraft(Id unitId) {
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        config.RES_Triggers_Off__c = false;
        upsert config;

        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Test.startTest();
        update new Product2(Id = unitId, RES_Unit_Status__c = 'Draft');
        Test.stopTest();
    }

    @isTest
    static void softHoldBundleUnitToDraft_cancelsQuotesAndContracts() {
        moveUnitToDraft(getUnitId(UNIT_NAME));

        Quote q = [SELECT Status, RES_Cancellation_Reason__c FROM Quote WHERE Name = 'RES UDC Test Quote'];
        Assert.areEqual('Cancelled', q.Status, 'Quote using the unit should be cancelled');
        Assert.areEqual(System.Label.RES_Unit_Draft_Cancellation_Reason, q.RES_Cancellation_Reason__c);
        Assert.areEqual('Proposal', [SELECT StageName FROM Opportunity WHERE Name = 'RES UDC Test Opportunity'].StageName, 'Primary quote cancelled resets the opportunity');

        for (Contract c : [SELECT Status, Description, RES_Cancellation_Reasons__c FROM Contract]) {
            Assert.areEqual('Canceled', c.Status, c.Description + ' contract should be cancelled');
            Assert.areEqual('24', c.RES_Cancellation_Reasons__c);
        }

        Product2 unit = [
            SELECT RES_Unit_Status__c, RES_Reserved_By_Quote__c, RES_Soft_Hold_Until__c, RES_Soft_Hold_Start__c
            FROM Product2 WHERE Name = :UNIT_NAME
        ];
        Assert.areEqual('Draft', unit.RES_Unit_Status__c, 'Cancelling the quote must not flip the unit back to Available');
        Assert.isNull(unit.RES_Reserved_By_Quote__c);
        Assert.isNull(unit.RES_Soft_Hold_Until__c);
        Assert.isNull(unit.RES_Soft_Hold_Start__c);
    }

    @isTest
    static void nonBundleUnitToDraft_leavesQuotesAndContracts() {
        moveUnitToDraft(getUnitId(NON_BUNDLE_UNIT_NAME));

        Assert.areEqual('Draft', [SELECT Status FROM Quote WHERE Name = 'RES UDC Non Bundle Quote'].Status);
        Assert.areEqual('Draft', [SELECT Status FROM Quote WHERE Name = 'RES UDC Test Quote'].Status);
        Assert.areEqual(0, [SELECT COUNT() FROM Contract WHERE Status = 'Canceled']);
    }

    @isTest
    static void pendingApprovalUnitToDraft_leavesQuotesAndContracts() {
        Id unitId = getUnitId(UNIT_NAME);
        update new Product2(Id = unitId, RES_Unit_Status__c = 'Pending Finance Approval');

        moveUnitToDraft(unitId);

        Assert.areEqual('Draft', [SELECT Status FROM Quote WHERE Name = 'RES UDC Test Quote'].Status);
        Assert.areEqual(0, [SELECT COUNT() FROM Contract WHERE Status = 'Canceled']);
    }

    @isTest
    static void alreadyCancelledContract_isNotTouched() {
        Contract cipContract = new Contract(Id = [SELECT ContractId FROM ContractItemPrice LIMIT 1].ContractId);
        cipContract.Status = 'Canceled';
        update cipContract;
        Datetime before = [SELECT LastModifiedDate FROM Contract WHERE Id = :cipContract.Id].LastModifiedDate;

        moveUnitToDraft(getUnitId(UNIT_NAME));

        Contract reloaded = [SELECT Status, RES_Cancellation_Reasons__c FROM Contract WHERE Id = :cipContract.Id];
        Assert.areEqual('Canceled', reloaded.Status);
        Assert.isNull(reloaded.RES_Cancellation_Reasons__c, 'Closed contracts must be skipped');
        Assert.areEqual('Canceled', [SELECT Contract.Status FROM Quote WHERE Name = 'RES UDC Test Quote'].Contract.Status);
    }

    @isTest
    static void isMovingToDraft_coversReleasableStatuses() {
        Id rtId = residentialSalesRecordTypeId();
        for (String status : new List<String>{ 'Available', 'Soft Hold', 'Hard Block' }) {
            Assert.isTrue(RES_UnitDraftCancellationService.isMovingToDraft(
                new Product2(RecordTypeId = rtId, Type = 'Bundle', RES_Unit_Status__c = 'Draft'),
                new Product2(RecordTypeId = rtId, Type = 'Bundle', RES_Unit_Status__c = status)
            ), status);
        }
        Assert.isFalse(RES_UnitDraftCancellationService.isMovingToDraft(
            new Product2(RecordTypeId = rtId, Type = 'Bundle', RES_Unit_Status__c = 'Draft'),
            new Product2(RecordTypeId = rtId, Type = 'Bundle', RES_Unit_Status__c = 'Sold')
        ));
    }

    private static ApprovalSubmission fakeSubmission(String fakeId, Id relatedRecordId) {
        return (ApprovalSubmission) JSON.deserialize(
            '{"attributes":{"type":"ApprovalSubmission"},"Id":"' + fakeId + '","RelatedRecordId":"' + relatedRecordId + '"}',
            ApprovalSubmission.class
        );
    }

    @isTest
    static void recordsUnderApproval_areRevokedWithSystemComment() {
        Quote q = [SELECT Id, ContractId FROM Quote WHERE Name = 'RES UDC Test Quote'];
        Id cipContractId = [SELECT ContractId FROM ContractItemPrice LIMIT 1].ContractId;
        RES_UnitDraftCancellationService.mockInProgressSubmissions = new List<ApprovalSubmission>{
            fakeSubmission('9iP000000000001', q.Id),
            fakeSubmission('9iP000000000002', cipContractId)
        };

        moveUnitToDraft(getUnitId(UNIT_NAME));
        Test.getEventBus().deliver();

        List<RES_Review_Approval_Work_Item__e> events = RES_UnitDraftCancellationService.publishedReviewEvents;
        Assert.areEqual(2, events.size(), 'One revoke per in-progress submission');
        Map<String, RES_Review_Approval_Work_Item__e> eventsByAction = new Map<String, RES_Review_Approval_Work_Item__e>();
        for (RES_Review_Approval_Work_Item__e e : events) {
            Assert.areEqual('Cancel', e.RES_Approval_Decision__c);
            Assert.areEqual(System.Label.RES_Unit_Draft_Approval_Recall_Comment, e.RES_Approval_Comments__c);
            Assert.isTrue(String.valueOf(e.RES_Approval_Work_Item_Id__c).startsWith('9iP'));
            eventsByAction.put(e.RES_Post_Review_Action__c, e);
        }
        Assert.areEqual(q.Id, eventsByAction.get('QuoteCancellation').RES_QuoteId__c);
        Assert.areEqual(System.Label.RES_Unit_Draft_Cancellation_Reason, eventsByAction.get('QuoteCancellation').RES_Cancellation_Reason__c);
        Assert.areEqual(cipContractId, eventsByAction.get('ContractCancellation').RES_recordId__c);

        // Quote and CIP contract are cancelled by the revoke event handler; the quote's own contract had no approval so is cancelled directly
        Quote reloaded = [SELECT Status, RES_Cancellation_Reason__c FROM Quote WHERE Id = :q.Id];
        Assert.areEqual('Cancelled', reloaded.Status);
        Assert.areEqual(System.Label.RES_Unit_Draft_Cancellation_Reason, reloaded.RES_Cancellation_Reason__c);
        Contract cipContract = [SELECT Status, RES_Cancellation_Reasons__c FROM Contract WHERE Id = :cipContractId];
        Assert.areEqual('Canceled', cipContract.Status);
        Assert.isNull(cipContract.RES_Cancellation_Reasons__c, 'Contract under approval must go through the revoke path, not the direct update');
        Contract quoteContract = [SELECT Status, RES_Cancellation_Reasons__c FROM Contract WHERE Id = :q.ContractId];
        Assert.areEqual('Canceled', quoteContract.Status);
        Assert.areEqual('24', quoteContract.RES_Cancellation_Reasons__c);
    }
}
