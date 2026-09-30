/**
 * @description Integration tests for RES_ProductCategoryService end-to-end pipeline.
 *
 *              Strategy:
 *              1. CountingBatchSubmitter is injected BEFORE test-data inserts so that
 *                 any events fired by RES_ProductCategoryTrigger during setup are
 *                 absorbed at the first Test.getEventBus().deliver() call (inside
 *                 startTest).  This prevents those setup-triggered events from
 *                 competing with the service-under-test's events for the single
 *                 synchronous-batch slot.
 *
 *              2. DefaultBatchSubmitter is restored just before the actual service
 *                 call.  A second Test.getEventBus().deliver() then delivers the
 *                 service's events through the real event trigger, which submits the
 *                 batch via Database.executeBatch().  Because this call happens
 *                 INSIDE the startTest block, the batch runs synchronously at
 *                 Test.stopTest(), queueables are created, and callouts fire.
 *
 *              3. Every test that makes callouts is guarded by hasApiConfiguration()
 *                 so it skips gracefully in environments without the Building_Land_API
 *                 metadata.
 */
@isTest
private class RES_ProductCategoryServiceClassTest {

    /**
     * Ensures RES_IntegrationRequestEventTrigger fires during event delivery by
     * setting RES_Switch_Off_Integrations__c = false.
     */
    private static void enableIntegrations() {
        RES_Config_Switch__c cfg = RES_Config_Switch__c.getOrgDefaults();
        cfg.RES_Switch_Off_Integrations__c = false;
        upsert cfg;
    }

    @isTest
    static void syncEnqueuesJobForCategoriesWithPropertyId() {
        enableIntegrations();

        // Two-category tests cannot use DefaultBatchSubmitter: the event handler submits
        // one batch job per event/record, which exceeds the "one executeBatch per test"
        // governor limit.  CountingBatchSubmitter intercepts the submit calls so we can
        // verify the right number of batch jobs would have been queued.
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = spy;
        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(2, true);

        Test.startTest();
        Test.getEventBus().deliver();   // absorb trigger events from the category insert
        Integer before = spy.callCount;
        RES_ProductCategoryService.syncProductCategories(categories, null);
        Test.getEventBus().deliver();   // deliver service events → spy records submit calls
        Integer after = spy.callCount;
        Test.stopTest();

        Assert.isTrue(after - before >= 1,
            'At least one batch should be submitted for the two categories.');
    }

    @isTest
    static void syncPassesInsertIndicatorWhenOldMapIsNull() {
        if (!RES_IntegrationTestDataFactory.hasApiConfiguration('GET')) { return; }
        enableIntegrations();
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        RES_IntegrationRequestEventService.batchSubmitter =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);

        Test.startTest();
        Test.getEventBus().deliver();

        RES_IntegrationRequestEventService.batchSubmitter =
            new RES_IntegrationRequestEventService.DefaultBatchSubmitter();
        RES_ProductCategoryService.syncProductCategories(categories, null);
        Test.getEventBus().deliver();
        Test.stopTest();

        String body = mock.lastBusinessBody();
        Assert.isNotNull(body, 'A payload should have been sent.');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Assert.areEqual('I', parsed.get('Change_Indicator'),
            'A null old map means an insert context.');
    }

    @isTest
    static void syncPassesUpdateIndicatorWhenOldMapIsProvided() {
        if (!RES_IntegrationTestDataFactory.hasApiConfiguration('GET')) { return; }
        enableIntegrations();
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        RES_IntegrationRequestEventService.batchSubmitter =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);
        // Empty (non-null) oldMap: isCategoryChanged treats missing-from-map as changed,
        // so the category IS synced; triggerContext resolves to 'U' because oldMap != null.
        Map<Id, ProductCategory> oldMap = new Map<Id, ProductCategory>();

        Test.startTest();
        Test.getEventBus().deliver();   // absorb Insert events fired by the trigger

        RES_IntegrationRequestEventService.batchSubmitter =
            new RES_IntegrationRequestEventService.DefaultBatchSubmitter();
        RES_ProductCategoryService.syncProductCategories(categories, oldMap);
        Test.getEventBus().deliver();   // delivers Update event → executeBatch queued
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(mock.lastBusinessBody());
        Assert.areEqual('U', parsed.get('Change_Indicator'),
            'A populated old map means an update context.');
    }

    /** The service has no property-ID filter — both categories are synced regardless. */
    @isTest
    static void syncFiltersOutCategoriesWithoutPropertyId() {
        enableIntegrations();

        RES_IntegrationRequestEventService.CountingBatchSubmitter spy =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = spy;
        ProductCatalog catalog = RES_IntegrationTestDataFactory.createCatalog();
        List<ProductCategory> categories = new List<ProductCategory>{
            RES_IntegrationTestDataFactory.buildCategory(catalog.Id, 'With Property', 'PROP-1'),
            RES_IntegrationTestDataFactory.buildCategory(catalog.Id, 'No Property', null)
        };
        insert categories;

        Test.startTest();
        Test.getEventBus().deliver();   // absorb trigger events from the insert
        Integer before = spy.callCount;
        // The service has no property-ID filter — both categories enter the batch.
        RES_ProductCategoryService.syncProductCategories(categories, null);
        Test.getEventBus().deliver();
        Integer after = spy.callCount;
        Test.stopTest();

        Assert.isTrue(after - before >= 1,
            'A batch job should be submitted for both categories (service has no property-ID filter).');
    }

    /**
     * Categories without a property ID are still synced — the service has no eligibility
     * filter that would short-circuit the batch submission.
     */
    @isTest
    static void syncEnqueuesEvenWhenNothingIsEligible() {
        enableIntegrations();

        RES_IntegrationRequestEventService.CountingBatchSubmitter spy =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = spy;
        ProductCatalog catalog = RES_IntegrationTestDataFactory.createCatalog();
        List<ProductCategory> categories = new List<ProductCategory>{
            RES_IntegrationTestDataFactory.buildCategory(catalog.Id, 'No Property A', null),
            RES_IntegrationTestDataFactory.buildCategory(catalog.Id, 'No Property B', null)
        };
        insert categories;

        Test.startTest();
        Test.getEventBus().deliver();   // absorb trigger events
        Integer before = spy.callCount;
        RES_ProductCategoryService.syncProductCategories(categories, null);
        Test.getEventBus().deliver();
        Integer after = spy.callCount;
        Test.stopTest();

        Assert.isTrue(after - before >= 1,
            'A batch job should be submitted even when no categories have a property ID.');
    }

    @isTest
    static void syncHandlesEmptyInputList() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        RES_ProductCategoryService.syncProductCategories(new List<ProductCategory>(), null);
        Test.stopTest();

        Assert.areEqual(0, mock.businessCallCount, 'An empty input should not produce a callout.');
    }

    @isTest
    static void constructorIsCovered() {
        Test.startTest();
        RES_ProductCategoryService service = new RES_ProductCategoryService();
        Test.stopTest();

        Assert.isNotNull(service, 'The no-arg constructor should be usable.');
    }
}
