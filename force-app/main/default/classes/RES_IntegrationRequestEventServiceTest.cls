/**
 * @description Test class for RES_IntegrationRequestEventService.
 *
 *              Uses RES_IntegrationTestDataFactory for records, the SAP token cache
 *              and the endpoint-routing HTTP mock.
 *
 *              Notes:
 *              - Inserting ProductCategory / RES_Measurement__c fires the org's triggers, which
 *                publish RES_Integration_Request__e. Those events are delivered (and their
 *                Queueables run) at Test.stopTest(), so the token is primed and the mock is
 *                registered in EVERY test that inserts data.
 *              - Jobs enqueued by the code under test are counted with Limits.getQueueableJobs()
 *                between startTest() and stopTest(), so jobs from trigger-published events do not
 *                pollute the assertions.
 *              - Queueables that run at stopTest() need the deployed API configuration custom
 *                metadata. If it is missing, tests that insert data return early (see guard).
 */
@IsTest
private class RES_IntegrationRequestEventServiceTest {

    private static final String PC_SERVICE                   = 'ProductCategory_Sync';
    private static final String MEASUREMENT_SERVICE          = 'Measurement_Sync';
    private static final String MEASUREMENT_CATALOG_SERVICE  = 'Measurement_Sync_Catalog';
    private static final String PRODUCT_CATALOG_SERVICE      = 'ProductCatalog_Sync';

    private static RES_IntegrationTestDataFactory.EndpointRoutingMock mock;

    private static void setUpCallouts() {
        RES_IntegrationTestDataFactory.primeSapToken();
        mock = new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);
    }

    /** Custom metadata can't be created in tests; without it the queueable can't run. */
    private static Boolean integrationConfigured() {
        return RES_IntegrationTestDataFactory.hasApiConfiguration('GET');
    }

    private static RES_Integration_Request__e buildEvent(String service, String context, String recordIds) {
        return new RES_Integration_Request__e(
            RES_Request_Method__c     = 'GET',
            RES_Service_Name__c       = service,
            RES_Triggering_Context__c = context,
            RES_RecordIds__c          = recordIds
        );
    }

    private static String joinIds(List<sObject> records) {
        List<String> ids = new List<String>();
        for (sObject s : records) {
            ids.add((String) s.Id);
        }
        return String.join(ids, ',');
    }

    /** Runs handleIntegrations and returns how many queueable jobs that call itself enqueued. */
    private static Integer handleAndCountJobs(List<RES_Integration_Request__e> events) {
        setUpCallouts();
        Test.startTest();
        RES_IntegrationRequestEventService.handleIntegrations(events);
        Integer enqueued = Limits.getQueueableJobs();
        Test.stopTest();
        return enqueued;
    }

    @IsTest
    static void handleIntegrations_productCategoryInsert_enqueuesJob() {
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(2, true);

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(PC_SERVICE, 'I', joinIds(cats)) }
        );

        System.assertEquals(1, enqueued, 'One queueable should be enqueued for PC insert');
        System.assertEquals(0, mock.tokenCallCount, 'Primed token should avoid the token callout');
    }

    @IsTest
    static void handleIntegrations_productCategoryUpdate_enqueuesJob() {
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(2, true);

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(PC_SERVICE, 'U', joinIds(cats)) }
        );

        System.assertEquals(1, enqueued, 'One queueable should be enqueued for PC update');
    }

    @IsTest
    static void handleIntegrations_measurementInsert_enqueuesJob() {
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(1, true);
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurements(cats[0].Id, 2);

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(MEASUREMENT_SERVICE, 'I', joinIds(measurements)) }
        );

        System.assertEquals(1, enqueued, 'One queueable should be enqueued for Measurement insert');
    }

    @IsTest
    static void handleIntegrations_measurementUpdate_enqueuesJob() {
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(1, true);
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurements(cats[0].Id, 2);

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(MEASUREMENT_SERVICE, 'U', joinIds(measurements)) }
        );

        System.assertEquals(1, enqueued, 'One queueable should be enqueued for Measurement update');
    }

    @IsTest
    static void handleIntegrations_multipleEventsSameKey_enqueuesSingleJob() {
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(2, true);

        // Same key twice; second event repeats an Id (dedup), has whitespace and a trailing comma
        List<RES_Integration_Request__e> events = new List<RES_Integration_Request__e>{
            buildEvent(PC_SERVICE, 'I', (String) cats[0].Id),
            buildEvent(PC_SERVICE, 'I', cats[0].Id + ' , ' + cats[1].Id + ',')
        };

        System.assertEquals(1, handleAndCountJobs(events), 'Events with the same key should be grouped into one job');
    }

    @IsTest
    static void handleIntegrations_mixedServicesAndContexts_enqueuesOneJobPerGroup() {
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(1, true);
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurements(cats[0].Id, 1);

        List<RES_Integration_Request__e> events = new List<RES_Integration_Request__e>{
            buildEvent(PC_SERVICE, 'I', joinIds(cats)),
            buildEvent(PC_SERVICE, 'U', joinIds(cats)),
            buildEvent(MEASUREMENT_SERVICE, 'I', joinIds(measurements)),
            buildEvent(MEASUREMENT_SERVICE, 'U', joinIds(measurements))
        };

        System.assertEquals(4, handleAndCountJobs(events), 'Each service/context group should enqueue its own job');
    }

    @IsTest
    static void handleIntegrations_blankRecordIds_enqueuesNothing() {
        List<RES_Integration_Request__e> events = new List<RES_Integration_Request__e>{
            buildEvent(PC_SERVICE, 'I', null),
            buildEvent(PC_SERVICE, 'U', '   '),
            buildEvent(MEASUREMENT_SERVICE, 'I', ''),
            buildEvent(MEASUREMENT_SERVICE, 'U', ' , , ')
        };

        System.assertEquals(0, handleAndCountJobs(events), 'No job when there are no record Ids');
    }

    @IsTest
    static void handleIntegrations_unknownServiceOrContext_enqueuesNothing() {
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(1, true);

        List<RES_Integration_Request__e> events = new List<RES_Integration_Request__e>{
            buildEvent('Unknown_Sync', 'I', joinIds(cats)),
            buildEvent(PC_SERVICE, 'D', joinIds(cats))
        };

        System.assertEquals(0, handleAndCountJobs(events), 'Unrecognised service/context combos should be ignored');
    }

    @IsTest
    static void handleIntegrations_noMatchingRecords_enqueuesNothing() {
        // Valid Id format, but no such record -> DAO returns empty -> enqueueService skips
        Id fakeId = Id.valueOf(ProductCategory.SObjectType.getDescribe().getKeyPrefix() + '000000000001');

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(PC_SERVICE, 'I', (String) fakeId) }
        );

        System.assertEquals(0, enqueued, 'No job when the DAO returns no records');
    }

    @IsTest
    static void handleIntegrations_invalidIdString_throwsStringException() {
        // Documents current behaviour: the (Id) cast is unguarded, so bad data throws
        Boolean threw = false;
        try {
            RES_IntegrationRequestEventService.handleIntegrations(
                new List<RES_Integration_Request__e>{ buildEvent(PC_SERVICE, 'I', 'not-an-id') }
            );
        } catch (System.StringException e) {
            threw = true;
        }
        System.assert(threw, 'An invalid Id string currently surfaces as a StringException');
    }

    @IsTest
    static void handleIntegrations_emptyList_doesNothing() {
        System.assertEquals(0, handleAndCountJobs(new List<RES_Integration_Request__e>()));
    }

    @IsTest
    static void enqueueService_validArgs_enqueuesJob() {
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(1, true);

        setUpCallouts();
        Test.startTest();
        RES_IntegrationRequestEventService.enqueueService(PC_SERVICE, cats, 'I', 'GET');
        Integer enqueued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(1, enqueued);
    }

    @IsTest
    static void enqueueService_invalidArgs_enqueuesNothing() {
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(1, true);

        setUpCallouts();
        Test.startTest();
        RES_IntegrationRequestEventService.enqueueService('', cats, 'I', 'GET');                        // blank service
        RES_IntegrationRequestEventService.enqueueService(PC_SERVICE, new List<sObject>(), 'I', 'GET'); // empty records
        RES_IntegrationRequestEventService.enqueueService(PC_SERVICE, cats, null, 'GET');               // blank context
        RES_IntegrationRequestEventService.enqueueService(PC_SERVICE, cats, 'I', '');                   // blank method
        Integer enqueued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(0, enqueued, 'Guard clauses should prevent enqueueing');
    }

    // ------------------------------------------------------------------
    // ProductCatalog_Sync
    // ------------------------------------------------------------------

    @IsTest
    static void handleIntegrations_productCatalogInsert_enqueuesJob() {
        if (!integrationConfigured()) { return; }
        ProductCatalog catalog = RES_IntegrationTestDataFactory.createCatalog();

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(PRODUCT_CATALOG_SERVICE, 'I', (String) catalog.Id) }
        );

        System.assertEquals(1, enqueued, 'One queueable should be enqueued for ProductCatalog insert');
    }

    @IsTest
    static void handleIntegrations_productCatalogUpdate_enqueuesJob() {
        if (!integrationConfigured()) { return; }
        ProductCatalog catalog = RES_IntegrationTestDataFactory.createCatalog();

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(PRODUCT_CATALOG_SERVICE, 'U', (String) catalog.Id) }
        );

        System.assertEquals(1, enqueued, 'One queueable should be enqueued for ProductCatalog update');
    }

    @IsTest
    static void handleIntegrations_productCatalogMultipleEvents_enqueuesSingleJob() {
        if (!integrationConfigured()) { return; }
        ProductCatalog cat1 = RES_IntegrationTestDataFactory.createCatalog();
        ProductCatalog cat2 = RES_IntegrationTestDataFactory.createCatalog();

        List<RES_Integration_Request__e> events = new List<RES_Integration_Request__e>{
            buildEvent(PRODUCT_CATALOG_SERVICE, 'I', (String) cat1.Id),
            buildEvent(PRODUCT_CATALOG_SERVICE, 'I', (String) cat2.Id)
        };

        System.assertEquals(1, handleAndCountJobs(events), 'Multiple ProductCatalog insert events should batch into one job');
    }

    @IsTest
    static void handleIntegrations_productCatalogNoMatchingRecord_enqueuesNothing() {
        Id fakeId = Id.valueOf(ProductCatalog.SObjectType.getDescribe().getKeyPrefix() + '000000000001');

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(PRODUCT_CATALOG_SERVICE, 'I', (String) fakeId) }
        );

        System.assertEquals(0, enqueued, 'No job when the DAO returns no ProductCatalog records');
    }
    
    @IsTest
    static void handleIntegrations_measurementCatalogInsert_enqueuesJob() {
        if (!integrationConfigured()) { return; }
        ProductCatalog catalog = RES_IntegrationTestDataFactory.createCatalog();
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurementsForCatalog(catalog.Id, 2);

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(MEASUREMENT_CATALOG_SERVICE, 'I', joinIds(measurements)) }
        );

        System.assertEquals(1, enqueued, 'One queueable should be enqueued for Measurement_Sync_Catalog insert');
    }

    @IsTest
    static void handleIntegrations_measurementCatalogUpdate_enqueuesJob() {
        if (!integrationConfigured()) { return; }
        ProductCatalog catalog = RES_IntegrationTestDataFactory.createCatalog();
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurementsForCatalog(catalog.Id, 2);

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(MEASUREMENT_CATALOG_SERVICE, 'U', joinIds(measurements)) }
        );

        System.assertEquals(1, enqueued, 'One queueable should be enqueued for Measurement_Sync_Catalog update');
    }

    @IsTest
    static void handleIntegrations_measurementCatalogMultipleEvents_enqueuesSingleJob() {
        if (!integrationConfigured()) { return; }
        ProductCatalog catalog = RES_IntegrationTestDataFactory.createCatalog();
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurementsForCatalog(catalog.Id, 2);

        List<RES_Integration_Request__e> events = new List<RES_Integration_Request__e>{
            buildEvent(MEASUREMENT_CATALOG_SERVICE, 'I', (String) measurements[0].Id),
            buildEvent(MEASUREMENT_CATALOG_SERVICE, 'I', measurements[0].Id + ' , ' + measurements[1].Id + ',')
        };

        System.assertEquals(1, handleAndCountJobs(events), 'Multiple Measurement_Sync_Catalog insert events should batch into one job');
    }

    @IsTest
    static void handleIntegrations_measurementCatalogNoMatchingRecord_enqueuesNothing() {
        Id fakeId = Id.valueOf(RES_Measurement__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(MEASUREMENT_CATALOG_SERVICE, 'I', (String) fakeId) }
        );

        System.assertEquals(0, enqueued, 'No job when the DAO returns no Measurement_Sync_Catalog records');
    }

    @IsTest
    static void constructor_canBeInstantiated() {
        System.assertNotEquals(null, new RES_IntegrationRequestEventService());
    }

    @IsTest
    static void publishEvent_deliversToService() {
        // Meaningful only if a trigger on RES_Integration_Request__e calls handleIntegrations
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(1, true);

        setUpCallouts();
        Test.startTest();
        Database.SaveResult sr = EventBus.publish(buildEvent(PC_SERVICE, 'I', joinIds(cats)));
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assert(sr.isSuccess(), 'Event should publish successfully');
        // Delivery is async, so verify via AsyncApexJob (>= because record inserts also publish events)
        Integer jobs = [
            SELECT COUNT() FROM AsyncApexJob
            WHERE JobType = 'Queueable' AND ApexClass.Name = 'RES_IntegrationQueueable'
        ];
        System.assert(jobs >= 1, 'Delivered event should have enqueued the integration job');
    }
}