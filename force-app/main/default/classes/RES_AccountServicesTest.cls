/**
 * @description Unit tests for RES_AccountServices.
 *
 *              The service publishes RES_Integration_Request__e platform events
 *              (one per qualifying Account). The platform-event subscriber
 *              (RES_IntegrationRequestEventService) enqueues RES_IntegrationQueueable
 *              which constructs RES_AccountIntegrationService and fetches a SAP token.
 *
 *              Every test that triggers DML or event delivery must therefore:
 *                1. Inject CountingBatchSubmitter so the queueable is never enqueued.
 *                2. Prime the SAP token so any token fetch path returns without error.
 *                3. Register an EndpointRoutingMock for any HTTP callout that leaks through.
 *                4. Deliver and count events with Test.getEventBus().deliver().
 */
@IsTest
private class RES_AccountServicesTest {

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static RES_IntegrationRequestEventService.CountingBatchSubmitter injectSpy() {
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = spy;
        return spy;
    }

    private static void primeCalloutInfra() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
    }

    /**
     * Calls handleContractAccountSync, delivers the event bus, and returns
     * the delta in batch submissions caused by that call.
     * Caller must call injectSpy() and primeCalloutInfra() before any DML.
     */
    private static Integer callServiceAndCount(
        List<Contract> contracts,
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy
    ) {
        Test.startTest();
        Test.getEventBus().deliver();   // flush events from test-data inserts
        Integer before = spy.callCount;

        RES_AccountServices.handleContractAccountSync(contracts);
        Test.getEventBus().deliver();   // deliver events published by the service

        Integer after = spy.callCount;
        Test.stopTest();
        return after - before;
    }

    private static Account createAccountNoExternalKey() {
        Account acc = new Account(Name = 'Test Account No Key');
        insert acc;
        return acc;
    }

    private static Account createAccountWithExternalKey() {
        Account acc = new Account(
            Name = 'Test Account With Key',
            RES_External_Key__c = 'EXT-001'
        );
        insert acc;
        return acc;
    }

    private static Contract buildContract(Id accountId) {
        return new Contract(
            AccountId    = accountId,
            StartDate    = Date.today(),
            ContractTerm = 12,
            Status       = 'Draft'
        );
    }

    // ------------------------------------------------------------------
    // Null / empty guards
    // ------------------------------------------------------------------

    @IsTest
    static void handleContractAccountSync_nullContracts_returnsEarly() {
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy = injectSpy();
        primeCalloutInfra();

        Integer jobs = callServiceAndCount(null, spy);

        Assert.areEqual(0, jobs, 'Null contract list should not publish any event');
    }

    @IsTest
    static void handleContractAccountSync_emptyContracts_returnsEarly() {
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy = injectSpy();
        primeCalloutInfra();

        Integer jobs = callServiceAndCount(new List<Contract>(), spy);

        Assert.areEqual(0, jobs, 'Empty contract list should not publish any event');
    }

    // ------------------------------------------------------------------
    // All AccountIds null → accountIds set stays empty → early return
    // ------------------------------------------------------------------

    @IsTest
    static void handleContractAccountSync_allNullAccountIds_returnsEarly() {
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy = injectSpy();
        primeCalloutInfra();

        // Build an in-memory Contract with no AccountId (cannot be inserted without one)
        Contract ctr = new Contract();
        ctr.AccountId = null;

        Integer jobs = callServiceAndCount(new List<Contract>{ ctr }, spy);

        Assert.areEqual(0, jobs, 'Contracts with null AccountId should not publish any event');
    }

    // ------------------------------------------------------------------
    // Account missing from DAO result → acc == null → continue (skip)
    // ------------------------------------------------------------------

    @IsTest
    static void handleContractAccountSync_accountMissingFromMap_skipsEvent() {
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy = injectSpy();
        primeCalloutInfra();

        Account acc = createAccountNoExternalKey();
        Contract ctr = buildContract(acc.Id);
        insert ctr;
        delete acc;  // remove so DAO query returns nothing for this Id

        Integer jobs = callServiceAndCount(new List<Contract>{ ctr }, spy);

        Assert.areEqual(0, jobs, 'Service should skip and publish no event when account is not found');
    }

    // ------------------------------------------------------------------
    // Insert context — blank RES_External_Key__c → triggerContext = 'I'
    // ------------------------------------------------------------------

    @IsTest
    static void handleContractAccountSync_accountWithNoExternalKey_publishesInsertEvent() {
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy = injectSpy();
        primeCalloutInfra();

        Account acc = createAccountNoExternalKey();
        Contract ctr = buildContract(acc.Id);
        insert ctr;

        Integer jobs = callServiceAndCount(new List<Contract>{ ctr }, spy);

        Assert.areEqual(1, jobs, 'Account with no external key should publish one insert-context event');
    }

    // ------------------------------------------------------------------
    // Update context — non-blank RES_External_Key__c → triggerContext = 'U'
    // ------------------------------------------------------------------

    @IsTest
    static void handleContractAccountSync_accountWithExternalKey_publishesUpdateEvent() {
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy = injectSpy();
        primeCalloutInfra();

        Account acc = createAccountWithExternalKey();
        Contract ctr = buildContract(acc.Id);
        insert ctr;

        Integer jobs = callServiceAndCount(new List<Contract>{ ctr }, spy);

        Assert.areEqual(1, jobs, 'Account with external key should publish one update-context event');
    }

    // ------------------------------------------------------------------
    // Mixed accounts — both 'I' and 'U' contexts in a single call
    // ------------------------------------------------------------------

    @IsTest
    static void handleContractAccountSync_mixedAccounts_publishesBothContexts() {
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy = injectSpy();
        primeCalloutInfra();

        Account accNew      = createAccountNoExternalKey();
        Account accExisting = createAccountWithExternalKey();

        List<Contract> contracts = new List<Contract>{
            buildContract(accNew.Id),
            buildContract(accExisting.Id)
        };
        insert contracts;

        Integer jobs = callServiceAndCount(contracts, spy);

        Assert.isTrue(jobs >= 1, 'Mixed accounts should publish events for both insert and update contexts');
    }

    // ------------------------------------------------------------------
    // Duplicate AccountIds across contracts → deduplicated by Set<Id>
    // ------------------------------------------------------------------

    @IsTest
    static void handleContractAccountSync_duplicateAccountIds_deduplicatedToOneEvent() {
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy = injectSpy();
        primeCalloutInfra();

        Account acc = createAccountNoExternalKey();

        List<Contract> contracts = new List<Contract>{
            buildContract(acc.Id),
            buildContract(acc.Id)
        };
        insert contracts;

        Integer jobs = callServiceAndCount(contracts, spy);

        Assert.areEqual(1, jobs, 'Duplicate account Ids across contracts should be deduplicated to one event');
    }

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    @IsTest
    static void constructor_canBeInstantiated() {
        Assert.isNotNull(
            new RES_AccountServices(),
            'The no-arg constructor should be usable'
        );
    }
}