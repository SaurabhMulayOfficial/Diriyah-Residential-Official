/**
 * @description Unit tests for RES_IntegrationAPIRouterBatch.
 *
 *              Design notes:
 *              - In-memory SObjects are used for all tests so no DML triggers
 *                fire and no competing Database.executeBatch calls arrive from
 *                the integration event service at Test.stopTest().
 *              - An unrecognised service name ('__test__') is supplied so that
 *                the enqueued RES_IntegrationQueueable is a no-op; this avoids
 *                needing callout mocks for pure batch-behaviour assertions.
 *              - execute() is called directly (not via Database.executeBatch)
 *                for null/empty-scope guard tests to preserve the one-batch
 *                allowance for tests that need the full batch pipeline.
 *              - After Test.stopTest(), queueable submissions are verified via
 *                AsyncApexJob so the assertion is independent of Limits counters.
 */
@IsTest
private class RES_IntegrationAPIRouterBatchTest {

    private static final String SERVICE = '__test__';  // unrecognised → queueable is a no-op
    private static final String METHOD  = 'GET';
    private static final String CONTEXT = 'I';

    private static List<SObject> inMemoryRecords(Integer count) {
        List<SObject> records = new List<SObject>();
        for (Integer i = 0; i < count; i++) {
            records.add(new ProductCategory(Name = 'Cat-' + i));
        }
        return records;
    }

    private static Integer queueableJobCount() {
        return [
            SELECT COUNT() FROM AsyncApexJob
            WHERE JobType = 'Queueable' AND ApexClass.Name = 'RES_IntegrationQueueable'
        ];
    }

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    @IsTest
    static void constructor_canBeInstantiated() {
        RES_IntegrationAPIRouterBatch batch = new RES_IntegrationAPIRouterBatch(
            inMemoryRecords(1), SERVICE, METHOD, CONTEXT
        );
        System.assertNotEquals(null, batch, 'Batch should be constructible with all four arguments');
    }

    // ------------------------------------------------------------------
    // start()
    // ------------------------------------------------------------------

    @IsTest
    static void start_returnsAllRecordsPassedToConstructor() {
        List<SObject> records = inMemoryRecords(3);
        RES_IntegrationAPIRouterBatch batch = new RES_IntegrationAPIRouterBatch(
            records, SERVICE, METHOD, CONTEXT
        );

        Iterable<SObject> iterable = batch.start(null);

        System.assertEquals(3, ((List<SObject>) iterable).size(),
            'start() should return exactly the records supplied to the constructor');
    }

    @IsTest
    static void start_withEmptyList_returnsEmptyIterable() {
        RES_IntegrationAPIRouterBatch batch = new RES_IntegrationAPIRouterBatch(
            new List<SObject>(), SERVICE, METHOD, CONTEXT
        );

        Iterable<SObject> iterable = batch.start(null);

        System.assertEquals(0, ((List<SObject>) iterable).size(),
            'start() should return an empty iterable when no records were supplied');
    }

    // ------------------------------------------------------------------
    // execute() — guard clauses (called directly to preserve batch budget)
    // ------------------------------------------------------------------

    @IsTest
    static void execute_nullScope_enqueuesNoJob() {
        RES_IntegrationAPIRouterBatch batch = new RES_IntegrationAPIRouterBatch(
            inMemoryRecords(1), SERVICE, METHOD, CONTEXT
        );

        Test.startTest();
        batch.execute(null, null);
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(0, queued, 'Null scope should not enqueue a queueable job');
    }

    @IsTest
    static void execute_emptyScope_enqueuesNoJob() {
        RES_IntegrationAPIRouterBatch batch = new RES_IntegrationAPIRouterBatch(
            inMemoryRecords(1), SERVICE, METHOD, CONTEXT
        );

        Test.startTest();
        batch.execute(null, new List<SObject>());
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(0, queued, 'Empty scope should not enqueue a queueable job');
    }

    // ------------------------------------------------------------------
    // execute() — full batch pipeline
    // ------------------------------------------------------------------

    @IsTest
    static void execute_oneRecord_enqueuesExactlyOneQueueable() {
        Integer before = queueableJobCount();

        Test.startTest();
        Database.executeBatch(
            new RES_IntegrationAPIRouterBatch(inMemoryRecords(1), SERVICE, METHOD, CONTEXT),
            1
        );
        Test.stopTest();

        System.assertEquals(1, queueableJobCount() - before,
            'One record should produce exactly one enqueued RES_IntegrationQueueable');
    }

    @IsTest
    static void execute_calledThreeTimes_enqueuesOneQueueableEachTime() {
        // Database.executeBatch with batch size 1 and N records calls execute() N times,
        // but Salesforce limits test methods to a single execute() invocation via executeBatch.
        // Call execute() directly three times to simulate what the batch runtime would do.
        RES_IntegrationAPIRouterBatch batch = new RES_IntegrationAPIRouterBatch(
            inMemoryRecords(3), SERVICE, METHOD, CONTEXT
        );
        List<SObject> records = inMemoryRecords(3);

        Test.startTest();
        batch.execute(null, new List<SObject>{ records[0] });
        batch.execute(null, new List<SObject>{ records[1] });
        batch.execute(null, new List<SObject>{ records[2] });
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(3, queued,
            'Each execute() call should enqueue exactly one RES_IntegrationQueueable');
    }

    @IsTest
    static void execute_usesOnlyScopeZero_ignoresExtraElementsInScope() {
        // If a caller passes batch size > 1, execute() should still only use the
        // first element and enqueue one queueable per execute() invocation.
        RES_IntegrationAPIRouterBatch batch = new RES_IntegrationAPIRouterBatch(
            inMemoryRecords(3), SERVICE, METHOD, CONTEXT
        );

        Test.startTest();
        // Simulate a single execute() call with a 3-record scope chunk
        batch.execute(null, inMemoryRecords(3));
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(1, queued,
            'execute() should always enqueue exactly one queueable, using only scope[0]');
    }

    // ------------------------------------------------------------------
    // finish()
    // ------------------------------------------------------------------

    @IsTest
    static void finish_completesWithoutException() {
        RES_IntegrationAPIRouterBatch batch = new RES_IntegrationAPIRouterBatch(
            inMemoryRecords(1), SERVICE, METHOD, CONTEXT
        );

        Boolean threw = false;
        try {
            batch.finish(null);
        } catch (Exception e) {
            threw = true;
        }

        System.assertEquals(false, threw, 'finish() should complete without throwing');
    }

    // ------------------------------------------------------------------
    // End-to-end: real service name with real records
    // ------------------------------------------------------------------

    @IsTest
    static void execute_productCategoryService_enqueuesQueueableForRealRecord() {
        // Inject counting submitter on the service so that trigger-fired events
        // from the category insert do NOT call Database.executeBatch and compete
        // with this test's own batch submission.
        RES_IntegrationRequestEventService.batchSubmitter =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();

        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(1, true);
        Integer before = queueableJobCount();

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Test.startTest();
        Database.executeBatch(
            new RES_IntegrationAPIRouterBatch(cats, 'ProductCategory_Sync', METHOD, CONTEXT),
            1
        );
        Test.stopTest();

        System.assertEquals(1, queueableJobCount() - before,
            'A real ProductCategory record with the correct service name should produce one queueable');
    }
}
