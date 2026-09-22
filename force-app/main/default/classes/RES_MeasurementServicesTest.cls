/**
 * @description Unit tests for RES_MeasurementServices.
 *
 *              The service does NOT enqueue a job itself: it publishes
 *              RES_Integration_Request__e platform events, and the subscriber
 *              (RES_IntegrationRequestEventService) enqueues RES_IntegrationQueueable.
 *              "Published" is therefore verified by the delta in queueable jobs around
 *              syncMeasurements() + Test.getEventBus().deliver(), which ignores jobs
 *              created by events fired from the test-data inserts.
 *
 *              For each changed measurement the service publishes TWO events:
 *              - Measurement_Sync         (for ProductCategory integration)
 *              - Measurement_Sync_Catalog (for ProductCatalog integration)
 *              The subscriber batches all events from a single delivery into one
 *              queueable job, so even with both event types published the delta
 *              in RES_IntegrationQueueable jobs is still 1 per syncMeasurements() call.
 *
 *              Dependencies that cannot be created in a test (custom metadata):
 *              - RES_SAP_Integration_Config__mdt 'Measurement_Sync' with RES_Sync_Fields__c
 *              - API configuration used by the integration service
 *              Tests that need them return early when they are not deployed; the
 *              "config missing" test runs only in that situation.
 */
@IsTest
private class RES_MeasurementServicesTest {

    private static final String CONFIG_NAME = 'Measurement_Sync';

    // Fields the factory populates; used to pick one that is NOT a sync field
    private static final List<String> CANDIDATE_FIELDS = new List<String>{
        'RES_Measurement_Amount__c',
        'RES_Measurement_Type__c',
        'RES_Measurement_From__c',
        'RES_Measurement_To__c'
    };

    private static RES_IntegrationTestDataFactory.EndpointRoutingMock mock;

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    private static void setUpCallouts() {
        RES_IntegrationTestDataFactory.primeSapToken();
        mock = new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);
    }

    /** Lower-cased sync field names from the deployed metadata (empty if missing/blank). */
    private static Set<String> getSyncFields() {
        Set<String> fields = new Set<String>();
        RES_SAP_Integration_Config__mdt cfg =
            new RES_SAPIntegrationConfigDAO().getSAPIntegrationConfigByDeveloperName(CONFIG_NAME);
        if (cfg != null && String.isNotBlank(cfg.RES_Sync_Fields__c)) {
            for (String f : cfg.RES_Sync_Fields__c.split(',')) {
                if (String.isNotBlank(f)) {
                    fields.add(f.trim().toLowerCase());
                }
            }
        }
        return fields;
    }

    private static Boolean configReady() {
        return !getSyncFields().isEmpty();
    }

    /** Config present AND the queueable can run at stopTest(). */
    private static Boolean canRun() {
        return configReady() && RES_IntegrationTestDataFactory.hasApiConfiguration('GET');
    }

    private static List<RES_Measurement__c> createMeasurements(Integer count) {
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(1, true);
        return RES_IntegrationTestDataFactory.createMeasurements(cats[0].Id, count);
    }

    /** First sync field that has a value on the record (so nulling it on "old" is a change). */
    private static String findPopulatedSyncField(RES_Measurement__c record) {
        for (String f : getSyncFields()) {
            if (record.get(f) != null) {
                return f;
            }
        }
        return null;
    }

    /** First factory-populated field that is not a sync field. */
    private static String findPopulatedNonSyncField(RES_Measurement__c record) {
        Set<String> syncFields = getSyncFields();
        for (String f : CANDIDATE_FIELDS) {
            if (!syncFields.contains(f.toLowerCase()) && record.get(f) != null) {
                return f;
            }
        }
        return null;
    }

    /**
     * Builds an "old" map from the records. For the first alterCount records, fieldToNull is
     * cleared so it differs from the "new" version.
     */
    private static Map<Id, RES_Measurement__c> buildOldMap(
        List<RES_Measurement__c> records, String fieldToNull, Integer alterCount
    ) {
        Map<Id, RES_Measurement__c> oldMap = new Map<Id, RES_Measurement__c>();
        for (Integer i = 0; i < records.size(); i++) {
            RES_Measurement__c old = records[i].clone(true);
            if (i < alterCount && fieldToNull != null) {
                old.put(fieldToNull, null);
            }
            oldMap.put(old.Id, old);
        }
        return oldMap;
    }

    private static Integer queueableJobCount() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            AND ApexClass.Name = 'RES_IntegrationQueueable'
        ];
    }

    /**
     * Calls syncMeasurements and returns how many integration jobs that call caused
     * (event published -> delivered -> subscriber enqueues job).
     */
    private static Integer syncAndCountJobs(
        List<RES_Measurement__c> records, Map<Id, RES_Measurement__c> oldMap
    ) {
        setUpCallouts();
        Test.startTest();
        Test.getEventBus().deliver();          // flush events fired by the test-data inserts
        Integer before = queueableJobCount();

        RES_MeasurementServices.syncMeasurements(records, oldMap);
        Test.getEventBus().deliver();          // deliver the event published by the service

        Integer after = queueableJobCount();
        Test.stopTest();
        return after - before;
    }

    // ------------------------------------------------------------------
    // Insert path (oldMap == null)
    // ------------------------------------------------------------------
    @IsTest
    static void sync_insert_publishesEventForAllRecords() {
        if (!canRun()) { return; }
        List<RES_Measurement__c> measurements = createMeasurements(2);

        Integer jobs = syncAndCountJobs(measurements, null);

        Assert.areEqual(1, jobs, 'A single job should cover all inserted measurements (both Measurement_Sync and Measurement_Sync_Catalog events are batched by the subscriber)');
        Assert.areEqual(0, mock.tokenCallCount, 'Primed token should avoid the token callout');
    }

    // ------------------------------------------------------------------
    // Update path
    // ------------------------------------------------------------------
    @IsTest
    static void sync_update_syncFieldChanged_publishesEvent() {
        if (!canRun()) { return; }
        List<RES_Measurement__c> measurements = createMeasurements(2);
        String field = findPopulatedSyncField(measurements[0]);
        if (field == null) { return; }

        Integer jobs = syncAndCountJobs(measurements, buildOldMap(measurements, field, measurements.size()));

        Assert.areEqual(1, jobs, 'A changed sync field should publish an event (subscriber batches both service names into one job)');
    }

    @IsTest
    static void sync_update_noChanges_publishesNothing() {
        if (!canRun()) { return; }
        List<RES_Measurement__c> measurements = createMeasurements(2);

        Integer jobs = syncAndCountJobs(measurements, buildOldMap(measurements, null, 0));

        Assert.areEqual(0, jobs, 'Identical old/new values should not publish an event');
    }

    @IsTest
    static void sync_update_onlyNonSyncFieldChanged_publishesNothing() {
        if (!canRun()) { return; }
        List<RES_Measurement__c> measurements = createMeasurements(2);
        String field = findPopulatedNonSyncField(measurements[0]);
        if (field == null) { return; }

        Integer jobs = syncAndCountJobs(measurements, buildOldMap(measurements, field, measurements.size()));

        Assert.areEqual(0, jobs, 'A change to a field outside RES_Sync_Fields__c must be ignored');
    }

    @IsTest
    static void sync_update_mixedChangedAndUnchanged_publishesSingleEvent() {
        if (!canRun()) { return; }
        List<RES_Measurement__c> measurements = createMeasurements(3);
        String field = findPopulatedSyncField(measurements[0]);
        if (field == null) { return; }

        // Only the first record differs from its "old" version
        Integer jobs = syncAndCountJobs(measurements, buildOldMap(measurements, field, 1));

        Assert.areEqual(1, jobs, 'Only changed records are synced; subscriber batches both service-name events into one job');
    }

    @IsTest
    static void sync_update_recordMissingFromOldMap_treatedAsChanged() {
        if (!canRun()) { return; }
        List<RES_Measurement__c> measurements = createMeasurements(1);

        // Non-null but empty oldMap -> oldMap.get(Id) is null -> isMeasurementChanged returns true
        Integer jobs = syncAndCountJobs(measurements, new Map<Id, RES_Measurement__c>());

        Assert.areEqual(1, jobs, 'A record absent from oldMap should be treated as changed; subscriber batches all events into one job');
    }

    // ------------------------------------------------------------------
    // Empty input
    // ------------------------------------------------------------------
    @IsTest
    static void sync_emptyList_insertContext_publishesNothing() {
        if (!canRun()) { return; }

        Integer jobs = syncAndCountJobs(new List<RES_Measurement__c>(), null);

        Assert.areEqual(0, jobs, 'Empty input should not publish an event');
    }

    @IsTest
    static void sync_emptyList_updateContext_publishesNothing() {
        if (!canRun()) { return; }

        Integer jobs = syncAndCountJobs(
            new List<RES_Measurement__c>(), new Map<Id, RES_Measurement__c>()
        );

        Assert.areEqual(0, jobs, 'Empty input should not publish an event');
    }

    // ------------------------------------------------------------------
    // Missing configuration (runs only when the metadata is NOT deployed/populated)
    // ------------------------------------------------------------------
    @IsTest
    static void sync_configMissing_throwsIntegrationException() {
        if (configReady()) { return; }

        Boolean threw = false;
        try {
            RES_MeasurementServices.syncMeasurements(new List<RES_Measurement__c>(), null);
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('SAP Integration Config'),
                'Message should explain the missing configuration'
            );
        }
        Assert.isTrue(threw, 'Missing config / sync fields should raise RES_IntegrationException');
    }

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------
    @IsTest
    static void constructor_canBeInstantiated() {
        Assert.isNotNull(new RES_MeasurementServices(), 'The no-arg constructor should be usable');
    }
}