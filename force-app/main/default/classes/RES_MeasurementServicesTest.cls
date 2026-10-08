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
 *              Measurements are sent as a child array of their parent, so the service
 *              publishes ONE event per unique parent of the changed measurements:
 *              - ProductCategory_Sync (per unique RES_Category__c)
 *              - ProductCatalog_Sync  (per unique RES_Catalog__c)
 *              plus Unit_Sync per unique product. The parent's context is 'I' while its
 *              RES_Last_Sync_DateTime__c is null, otherwise 'U'.
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

    /**
     * Calls syncMeasurements and returns how many batch submissions that call caused.
     * Uses CountingBatchSubmitter to avoid hitting the one-executeBatch-per-test limit and
     * to count the correct job type (BatchApex / RES_IntegrationAPIRouterBatch).
     */
    private static Integer syncAndCountJobs(
        List<RES_Measurement__c> records, Map<Id, RES_Measurement__c> oldMap
    ) {
        setUpCallouts();
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = spy;

        Test.startTest();
        Test.getEventBus().deliver();          // flush events fired by the test-data inserts
        Integer before = spy.callCount;

        RES_MeasurementServices.syncMeasurements(records, oldMap);
        Test.stopTest();                        // stopTest delivers events published by the service

        Integer after = spy.callCount;
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

        Assert.areEqual(1, jobs, 'A single job should cover all inserted measurements (parent category events are batched by the subscriber)');
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

        Assert.areEqual(1, jobs, 'A changed sync field should publish an event (subscriber batches the parent events into one job)');
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

        Assert.areEqual(1, jobs, 'Only changed records are synced; subscriber batches the parent events into one job');
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
    // Catalog sync path (forced via @TestVisible override)
    // ------------------------------------------------------------------
    @IsTest
    static void sync_catalogEnabled_publishesCatalogEvent() {
        if (!canRun()) { return; }

        ProductCatalog catalog = RES_IntegrationTestDataFactory.createCatalog();
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurementsForCatalog(catalog.Id, 1);

        Integer jobs = syncAndCountJobs(measurements, null);

        Assert.isTrue(jobs >= 1, 'Catalog sync enabled with RES_Catalog__c set must publish events');
    }

    @IsTest
    static void sync_insert_unitWithExternalId_publishesParentSync() {
        if (!canRun()) { return; }

        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId        = UserInfo.getOrganizationId(),
            RES_Triggers_Off__c = true
        );
        upsert cfg;

        Product2 p = new Product2(
            Name                       = 'TEST-MEAS-WITHEXT',
            IsActive                   = true,
            ProductCode                = 'PC-MWE-01',
            Family                     = '1004',
            RES_Type__c                = 'N',
            RES_Product_External_ID__c = '1000/140/99999999'  // unit already exists in SAP
        );
        insert p;

        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(1, true);
        RES_Measurement__c m = new RES_Measurement__c(
            RES_Product__c             = p.Id,
            RES_Category__c            = cats[0].Id,
            RES_Measurement_Type__c    = 'Z007',
            RES_Unit_Of_Measurement__c = 'Sqr Mtr',
            RES_Measurement_Amount__c  = 100,
            RES_Measurement_From__c    = Date.newInstance(2025, 1, 1),
            RES_Measurement_To__c      = Date.newInstance(2099, 12, 31)
        );
        insert m;

        cfg.RES_Triggers_Off__c = false;
        update cfg;

        m = [SELECT Id, RES_Product__c, RES_Category__c, RES_Catalog__c FROM RES_Measurement__c WHERE Id = :m.Id];

        Integer jobs = syncAndCountJobs(new List<RES_Measurement__c>{ m }, null);

        Assert.isTrue(jobs >= 1,
            'Parent sync must fire on INSERT when the related unit already has a SAP ExternalId');
    }

    // ------------------------------------------------------------------
    // Parent (category / catalog) events
    // ------------------------------------------------------------------
    @IsTest
    static void buildParentSyncEvents_oneEventPerUniqueParent_contextFromLastSync() {
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(2, true);
        ProductCatalog catalog = RES_IntegrationTestDataFactory.createCatalog();

        update new ProductCategory(Id = cats[1].Id, RES_Last_Sync_DateTime__c = System.now());

        List<RES_Integration_Request__e> events = RES_MeasurementServices.buildParentSyncEvents(
            new Set<Id>{ cats[0].Id, cats[1].Id },
            new Set<Id>{ catalog.Id }
        );

        Assert.areEqual(3, events.size(), 'Two categories + one catalog = three events');
        Map<String, String> contextByRecord = new Map<String, String>();
        for (RES_Integration_Request__e e : events) {
            Assert.areEqual('GET', e.RES_Request_Method__c);
            Assert.isTrue(e.RES_Service_Name__c == 'ProductCategory_Sync' || e.RES_Service_Name__c == 'ProductCatalog_Sync');
            contextByRecord.put(e.RES_RecordIds__c, e.RES_Triggering_Context__c);
        }
        Assert.areEqual('I', contextByRecord.get(String.valueOf(cats[0].Id)), 'Never-synced category is an insert');
        Assert.areEqual('U', contextByRecord.get(String.valueOf(cats[1].Id)), 'Already-synced category is an update');
        Assert.areEqual('I', contextByRecord.get(String.valueOf(catalog.Id)), 'Never-synced catalog is an insert');
    }

    @IsTest
    static void buildParentSyncEvents_emptyInput_returnsNoEvents() {
        Assert.isTrue(RES_MeasurementServices.buildParentSyncEvents(new Set<Id>(), new Set<Id>()).isEmpty());
        Assert.isTrue(RES_MeasurementServices.buildParentSyncEvents(null, null).isEmpty());
    }

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------
    @IsTest
    static void constructor_canBeInstantiated() {
        Assert.isNotNull(new RES_MeasurementServices(), 'The no-arg constructor should be usable');
    }
}