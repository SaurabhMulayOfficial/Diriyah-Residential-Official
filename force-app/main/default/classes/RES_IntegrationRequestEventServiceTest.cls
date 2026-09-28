/**
 * @description Test class for RES_IntegrationRequestEventService.
 *
 *              Uses RES_IntegrationTestDataFactory for records, the SAP token cache
 *              and the endpoint-routing HTTP mock.
 *
 *              Notes:
 *              - Inserting ProductCategory / RES_Measurement__c fires the org's triggers, which
 *                publish RES_Integration_Request__e. Those events are delivered at Test.stopTest(),
 *                causing additional Database.executeBatch calls that would hit Salesforce's
 *                "one executeBatch per test" limit and inflate AsyncApexJob counts.
 *              - To isolate only the batches submitted by the code under test, a CountingBatchSubmitter
 *                is injected before each assertion. It intercepts batchSubmitter.submit() calls and
 *                counts them WITHOUT forwarding to Database.executeBatch, so trigger-fired event
 *                deliveries at Test.stopTest() do not pollute counts or hit the batch limit.
 *              - The publishEvent_deliversToService test restores the real submitter so it can verify
 *                the end-to-end AsyncApexJob submission.
 */
@IsTest
private class RES_IntegrationRequestEventServiceTest {

    private static final String PC_SERVICE                   = 'ProductCategory_Sync';
    private static final String MEASUREMENT_SERVICE          = 'Measurement_Sync';
    private static final String MEASUREMENT_CATALOG_SERVICE  = 'Measurement_Sync_Catalog';
    private static final String PRODUCT_CATALOG_SERVICE      = 'ProductCatalog_Sync';

    private static RES_IntegrationTestDataFactory.EndpointRoutingMock mock;

    private static RES_IntegrationRequestEventService.CountingBatchSubmitter injectCountingSubmitter() {
        RES_IntegrationRequestEventService.CountingBatchSubmitter submitter =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = submitter;
        return submitter;
    }

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

    /**
     * Injects a counting mock, runs handleIntegrations, and returns only the batch
     * submissions made by that call — trigger-fired event deliveries at Test.stopTest()
     * also call the mock but those counts are irrelevant because they do not submit
     * real batches either.
     */
    private static Integer handleAndCountJobs(List<RES_Integration_Request__e> events) {
        setUpCallouts();
        RES_IntegrationRequestEventService.CountingBatchSubmitter submitter = injectCountingSubmitter();
        Test.startTest();
        RES_IntegrationRequestEventService.handleIntegrations(events);
        Integer submitted = submitter.callCount;
        Test.stopTest();
        return submitted;
    }

    @IsTest
    static void handleIntegrations_productCategoryInsert_enqueuesJob() {
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(2, true);

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(PC_SERVICE, 'I', joinIds(cats)) }
        );

        System.assertEquals(1, enqueued, 'One batch should be submitted for PC insert');
    }

    @IsTest
    static void handleIntegrations_productCategoryUpdate_enqueuesJob() {
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(2, true);

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(PC_SERVICE, 'U', joinIds(cats)) }
        );

        System.assertEquals(1, enqueued, 'One batch should be submitted for PC update');
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

        System.assertEquals(1, enqueued, 'One batch should be submitted for Measurement insert');
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

        System.assertEquals(1, enqueued, 'One batch should be submitted for Measurement update');
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
        RES_IntegrationRequestEventService.CountingBatchSubmitter submitter = injectCountingSubmitter();
        Test.startTest();
        RES_IntegrationRequestEventService.enqueueService(PC_SERVICE, cats, 'I', 'GET');
        Integer submitted = submitter.callCount;
        Test.stopTest();

        System.assertEquals(1, submitted);
    }

    @IsTest
    static void enqueueService_invalidArgs_enqueuesNothing() {
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(1, true);

        setUpCallouts();
        RES_IntegrationRequestEventService.CountingBatchSubmitter submitter = injectCountingSubmitter();
        Test.startTest();
        RES_IntegrationRequestEventService.enqueueService('', cats, 'I', 'GET');                        // blank service
        RES_IntegrationRequestEventService.enqueueService(PC_SERVICE, new List<sObject>(), 'I', 'GET'); // empty records
        RES_IntegrationRequestEventService.enqueueService(PC_SERVICE, cats, null, 'GET');               // blank context
        RES_IntegrationRequestEventService.enqueueService(PC_SERVICE, cats, 'I', '');                   // blank method
        Integer submitted = submitter.callCount;
        Test.stopTest();

        System.assertEquals(0, submitted, 'Guard clauses should prevent batch submission');
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

        System.assertEquals(1, enqueued, 'One batch should be submitted for ProductCatalog insert');
    }

    @IsTest
    static void handleIntegrations_productCatalogUpdate_enqueuesJob() {
        if (!integrationConfigured()) { return; }
        ProductCatalog catalog = RES_IntegrationTestDataFactory.createCatalog();

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent(PRODUCT_CATALOG_SERVICE, 'U', (String) catalog.Id) }
        );

        System.assertEquals(1, enqueued, 'One batch should be submitted for ProductCatalog update');
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

        System.assertEquals(1, enqueued, 'One batch should be submitted for Measurement_Sync_Catalog insert');
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

        System.assertEquals(1, enqueued, 'One batch should be submitted for Measurement_Sync_Catalog update');
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

    // ------------------------------------------------------------------
    // Sales_Contract_Creation / Sales_Contract_Update / Sales_Contract_Termination
    // ------------------------------------------------------------------

    @IsTest
    static void handleIntegrations_contractInsert_noMatchingRecord_enqueuesNothing() {
        Id fakeId = Id.valueOf(Contract.SObjectType.getDescribe().getKeyPrefix() + '000000000001');

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent('Sales_Contract_Creation', 'I', (String) fakeId) }
        );

        System.assertEquals(0, enqueued, 'No batch when DAO returns no Contract records for Sales_Contract_Creation');
    }

    @IsTest
    static void handleIntegrations_contractUpdate_noMatchingRecord_enqueuesNothing() {
        Id fakeId = Id.valueOf(Contract.SObjectType.getDescribe().getKeyPrefix() + '000000000002');

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent('Sales_Contract_Update', 'U', (String) fakeId) }
        );

        System.assertEquals(0, enqueued, 'No batch when DAO returns no Contract records for Sales_Contract_Update');
    }

    @IsTest
    static void handleIntegrations_contractTermination_noMatchingRecord_enqueuesNothing() {
        Id fakeId = Id.valueOf(Contract.SObjectType.getDescribe().getKeyPrefix() + '000000000003');

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent('Sales_Contract_Termination', 'U', (String) fakeId) }
        );

        System.assertEquals(0, enqueued, 'No batch when DAO returns no Contract records for Sales_Contract_Termination');
    }

    // ------------------------------------------------------------------
    // Payment_Plan
    // ------------------------------------------------------------------

    @IsTest
    static void handleIntegrations_paymentPlanInsert_noMatchingRecord_enqueuesNothing() {
        Id fakeId = Id.valueOf(Contract.SObjectType.getDescribe().getKeyPrefix() + '000000000004');

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent('Payment_Plan', 'I', (String) fakeId) }
        );

        System.assertEquals(0, enqueued, 'No batch when DAO returns no records for Payment_Plan insert');
    }

    @IsTest
    static void handleIntegrations_paymentPlanUpdate_noMatchingRecord_enqueuesNothing() {
        Id fakeId = Id.valueOf(Contract.SObjectType.getDescribe().getKeyPrefix() + '000000000005');

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent('Payment_Plan', 'U', (String) fakeId) }
        );

        System.assertEquals(0, enqueued, 'No batch when DAO returns no records for Payment_Plan update');
    }

    // ------------------------------------------------------------------
    // Installments
    // ------------------------------------------------------------------

    @IsTest
    static void handleIntegrations_installmentInsert_noMatchingRecord_enqueuesNothing() {
        Id fakeId = Id.valueOf(Contract.SObjectType.getDescribe().getKeyPrefix() + '000000000006');

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent('Installments', 'I', (String) fakeId) }
        );

        System.assertEquals(0, enqueued, 'No batch when DAO returns no records for Installments insert');
    }

    @IsTest
    static void handleIntegrations_installmentUpdate_noMatchingRecord_enqueuesNothing() {
        Id fakeId = Id.valueOf(Contract.SObjectType.getDescribe().getKeyPrefix() + '000000000007');

        Integer enqueued = handleAndCountJobs(
            new List<RES_Integration_Request__e>{ buildEvent('Installments', 'U', (String) fakeId) }
        );

        System.assertEquals(0, enqueued, 'No batch when DAO returns no records for Installments update');
    }

    // ------------------------------------------------------------------
    // Constructor / misc
    // ------------------------------------------------------------------

    @IsTest
    static void constructor_canBeInstantiated() {
        System.assertNotEquals(null, new RES_IntegrationRequestEventService());
    }

    @IsTest
    static void publishEvent_deliversToService() {
        // Meaningful only if a trigger on RES_Integration_Request__e calls handleIntegrations
        if (!integrationConfigured()) { return; }
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(1, true);

        // Use the real submitter so Database.executeBatch is actually called and AsyncApexJob is created.
        // Only ONE explicit batch is submitted here (the delivered event), so the one-batch-per-test
        // limit is respected.
        RES_IntegrationRequestEventService.batchSubmitter = new RES_IntegrationRequestEventService.DefaultBatchSubmitter();
        setUpCallouts();
        Test.startTest();
        Database.SaveResult sr = EventBus.publish(buildEvent(PC_SERVICE, 'I', joinIds(cats)));
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assert(sr.isSuccess(), 'Event should publish successfully');
        Integer jobs = [
            SELECT COUNT() FROM AsyncApexJob
            WHERE JobType = 'BatchApex' AND ApexClass.Name = 'RES_IntegrationAPIRouterBatch'
        ];
        System.assert(jobs >= 1, 'Delivered event should have submitted the integration batch');
    }
}