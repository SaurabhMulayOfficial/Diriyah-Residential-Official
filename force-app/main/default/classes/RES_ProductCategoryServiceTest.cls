/**
 * @description Unit tests for RES_ProductCategoryService.
 *
 *              The service does NOT enqueue a job itself: it publishes a
 *              RES_Integration_Request__e, and the platform-event subscriber
 *              (RES_IntegrationRequestEventService) enqueues RES_IntegrationQueueable.
 *              "Published" is therefore verified by the delta in queueable jobs around
 *              syncProductCategories() + Test.getEventBus().deliver(), which ignores jobs
 *              created by events fired from the test-data inserts.
 *
 *              Dependencies that cannot be created in a test (custom metadata):
 *              - RES_SAP_Integration_Config__mdt 'Product_Category_Sync' with RES_Sync_Fields__c
 *              - API configuration used by the integration service
 *              Tests that need them return early when they are not deployed; the
 *              "config missing" test runs only in that situation.
 *
 *              NOTE: sync_update_syncFieldChanged_publishesEvent exposes a bug in the service
 *              (the sync-field parsing loop iterates the empty syncFields set instead of
 *              syncFieldLst). It fails until that loop is fixed.
 */
@IsTest
private class RES_ProductCategoryServiceTest {

    private static final String CONFIG_NAME = 'Product_Category_Sync';

    // Fields the factory populates; used to pick one that is NOT a sync field
    private static final List<String> CANDIDATE_FIELDS = new List<String>{
        'Name',
        'RES_Company_Code__c',
        'RES_Business_Entity_Id__c',
        'RES_Property_ID__c',
        'RES_Valid_From_Date__c',
        'RES_Valid_To_Date__c',
        'RES_Profit_Center__c',
        'RES_Property_Type__c'
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

    /** First sync field that has a value on the record (so nulling it on "old" is a change). */
    private static String findPopulatedSyncField(ProductCategory record) {
        for (String f : getSyncFields()) {
            if (record.get(f) != null) {
                return f;
            }
        }
        return null;
    }

    /** First factory-populated field that is not a sync field. */
    private static String findPopulatedNonSyncField(ProductCategory record) {
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
    private static Map<Id, ProductCategory> buildOldMap(
        List<ProductCategory> records, String fieldToNull, Integer alterCount
    ) {
        Map<Id, ProductCategory> oldMap = new Map<Id, ProductCategory>();
        for (Integer i = 0; i < records.size(); i++) {
            ProductCategory old = records[i].clone(true);
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
     * Calls syncProductCategories and returns how many integration jobs that call caused
     * (event published -> delivered -> subscriber enqueues job).
     */
    private static Integer syncAndCountJobs(
        List<ProductCategory> records, Map<Id, ProductCategory> oldMap
    ) {
        setUpCallouts();
        Test.startTest();
        Test.getEventBus().deliver();          // flush events fired by the test-data inserts
        Integer before = queueableJobCount();

        RES_ProductCategoryService.syncProductCategories(records, oldMap);
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
        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(2, true);

        Integer jobs = syncAndCountJobs(categories, null);

        Assert.areEqual(1, jobs, 'A single event / job should cover all inserted categories');
        Assert.areEqual(0, mock.tokenCallCount, 'Primed token should avoid the token callout');
    }

    // ------------------------------------------------------------------
    // Update path
    // ------------------------------------------------------------------
    @IsTest
    static void sync_update_syncFieldChanged_publishesEvent() {
        if (!canRun()) { return; }
        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(2, true);
        String field = findPopulatedSyncField(categories[0]);
        if (field == null) { return; }

        Integer jobs = syncAndCountJobs(categories, buildOldMap(categories, field, categories.size()));

        // Fails today because of the empty-set loop bug in RES_ProductCategoryService
        Assert.areEqual(1, jobs, 'A changed sync field should publish an event');

        // The job runs at stopTest(); the update context should reach the payload
        Boolean sawUpdateIndicator = false;
        for (HttpRequest req : mock.businessRequests) {
            if (req.getBody() != null && req.getBody().contains('"Change_Indicator":"U"')) {
                sawUpdateIndicator = true;
            }
        }
        Assert.isTrue(sawUpdateIndicator, 'The update context (U) should flow through to the callout payload');
    }

    @IsTest
    static void sync_update_noChanges_publishesNothing() {
        if (!canRun()) { return; }
        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(2, true);

        Integer jobs = syncAndCountJobs(categories, buildOldMap(categories, null, 0));

        Assert.areEqual(0, jobs, 'Identical old/new values should not publish an event');
    }

    @IsTest
    static void sync_update_onlyNonSyncFieldChanged_publishesNothing() {
        if (!canRun()) { return; }
        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(2, true);
        String field = findPopulatedNonSyncField(categories[0]);
        if (field == null) { return; }

        Integer jobs = syncAndCountJobs(categories, buildOldMap(categories, field, categories.size()));

        Assert.areEqual(0, jobs, 'A change to a field outside RES_Sync_Fields__c must be ignored');
    }

    @IsTest
    static void sync_update_mixedChangedAndUnchanged_publishesSingleEvent() {
        if (!canRun()) { return; }
        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(3, true);
        String field = findPopulatedSyncField(categories[0]);
        if (field == null) { return; }

        // Only the first record differs from its "old" version
        Integer jobs = syncAndCountJobs(categories, buildOldMap(categories, field, 1));

        Assert.areEqual(1, jobs, 'Only changed records are synced, in one event');
    }

    @IsTest
    static void sync_update_recordMissingFromOldMap_treatedAsChanged() {
        if (!canRun()) { return; }
        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);

        // Non-null but empty oldMap -> oldMap.get(Id) is null -> isCategoryChanged returns true
        Integer jobs = syncAndCountJobs(categories, new Map<Id, ProductCategory>());

        Assert.areEqual(1, jobs, 'A record absent from oldMap should be treated as changed');
    }

    // ------------------------------------------------------------------
    // Empty input
    // ------------------------------------------------------------------
    @IsTest
    static void sync_emptyList_insertContext_publishesNothing() {
        if (!canRun()) { return; }

        Integer jobs = syncAndCountJobs(new List<ProductCategory>(), null);

        Assert.areEqual(0, jobs, 'Empty input should not publish an event');
    }

    @IsTest
    static void sync_emptyList_updateContext_publishesNothing() {
        if (!canRun()) { return; }

        Integer jobs = syncAndCountJobs(new List<ProductCategory>(), new Map<Id, ProductCategory>());

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
            RES_ProductCategoryService.syncProductCategories(new List<ProductCategory>(), null);
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
        Assert.isNotNull(new RES_ProductCategoryService(), 'The no-arg constructor should be usable');
    }

    // ------------------------------------------------------------------
    // processResponse (tested indirectly via syncProductCategories HTTP layer)
    // ------------------------------------------------------------------

    /** Mock that returns a single SAP success item. */
    private class SapSuccessResponseMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setBody('{"Return":{"item":{"type":"S","message":"Processed successfully","Number":"001","System":"SAP"}}}');
            return res;
        }
    }

    /** Mock that returns a single SAP error item. */
    private class SapErrorResponseMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setBody('{"Return":{"item":{"type":"E","message":"Validation failed","Number":"999","System":"SAP"}}}');
            return res;
        }
    }

    @IsTest
    static void processResponse_successItem_stampsLastSyncDateTime() {
        if (!RES_IntegrationTestDataFactory.hasApiConfiguration('POST')) { return; }
        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new SapSuccessResponseMock());

        Test.startTest();
        RES_ProductCategoryIntegrationService.syncProductCategories(categories, 'POST', 'I');
        Test.stopTest();

        ProductCategory updated = [
            SELECT RES_Last_Sync_DateTime__c
            FROM ProductCategory
            WHERE Id = :categories[0].Id
        ];
        Assert.isNotNull(
            updated.RES_Last_Sync_DateTime__c,
            'processResponse returning true (success item) should stamp RES_Last_Sync_DateTime__c'
        );
    }

    @IsTest
    static void processResponse_errorItem_doesNotStampLastSyncDateTime() {
        if (!RES_IntegrationTestDataFactory.hasApiConfiguration('POST')) { return; }
        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new SapErrorResponseMock());

        Test.startTest();
        RES_ProductCategoryIntegrationService.syncProductCategories(categories, 'POST', 'I');
        Test.stopTest();

        ProductCategory updated = [
            SELECT RES_Last_Sync_DateTime__c
            FROM ProductCategory
            WHERE Id = :categories[0].Id
        ];
        Assert.isNull(
            updated.RES_Last_Sync_DateTime__c,
            'processResponse returning false (error item) must not stamp RES_Last_Sync_DateTime__c'
        );
    }
}