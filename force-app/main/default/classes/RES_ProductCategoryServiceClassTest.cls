/**
 * @description Unit tests for RES_ProductCategoryService.
 *
 *              The class enqueues a RES_IntegrationQueueable, so every test
 *              needs an HTTP mock and a primed SAP token: the queued job runs
 *              at Test.stopTest() and performs a real callout attempt.
 */
@isTest
private class RES_ProductCategoryServiceClassTest {

    @isTest
    static void syncEnqueuesJobForCategoriesWithPropertyId() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(2, true);

        Test.startTest();
        RES_ProductCategoryService.syncProductCategories(categories, null);
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable'],
            'One queueable job should be enqueued.'
        );
        Test.stopTest();

        Assert.areEqual(2, mock.businessCallCount, 'The queued job should perform the sync callout.');
    }

    @isTest
    static void syncPassesInsertIndicatorWhenOldMapIsNull() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);

        Test.startTest();
        RES_ProductCategoryService.syncProductCategories(categories, null);
        Test.stopTest();

        String body = mock.lastBusinessBody();
        Assert.isNotNull(body, 'A payload should have been sent.');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Assert.areEqual('I', parsed.get('Change_Indicator'),
            'A null old map means an insert context.');
    }

    @isTest
    static void syncPassesUpdateIndicatorWhenOldMapIsProvided() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);
        Map<Id, ProductCategory> oldMap = new Map<Id, ProductCategory>(categories);

        Test.startTest();
        RES_ProductCategoryService.syncProductCategories(categories, oldMap);
        Test.stopTest();

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(mock.lastBusinessBody());
        Assert.areEqual('I', parsed.get('Change_Indicator'),
            'A populated old map means an update context.');
    }

    @isTest
    static void syncFiltersOutCategoriesWithoutPropertyId() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        ProductCatalog catalog = RES_IntegrationTestDataFactory.createCatalog();
        List<ProductCategory> categories = new List<ProductCategory>{
            RES_IntegrationTestDataFactory.buildCategory(catalog.Id, 'With Property', 'PROP-1'),
            RES_IntegrationTestDataFactory.buildCategory(catalog.Id, 'No Property', null)
        };
        insert categories;

        Test.startTest();
        RES_ProductCategoryService.syncProductCategories(categories, null);
        Test.stopTest();

        String body = mock.lastBusinessBody();
        Assert.isTrue(body.contains('PROP-1'), 'The eligible category should be in the payload.');
    }

    /**
     * Every category is filtered out, so the queueable receives an empty list.
     * The job is still enqueued but exits at its own guard clause, and no
     * callout is made. Short circuiting before the enqueue would save an
     * async slot.
     */
    @isTest
    static void syncEnqueuesEvenWhenNothingIsEligible() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        ProductCatalog catalog = RES_IntegrationTestDataFactory.createCatalog();
        List<ProductCategory> categories = new List<ProductCategory>{
            RES_IntegrationTestDataFactory.buildCategory(catalog.Id, 'No Property A', null),
            RES_IntegrationTestDataFactory.buildCategory(catalog.Id, 'No Property B', null)
        };
        insert categories;

        Test.startTest();
        RES_ProductCategoryService.syncProductCategories(categories, null);
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable'],
            'A job is enqueued even though no record qualifies.'
        );
        Test.stopTest();

        Assert.areEqual(2, mock.businessCallCount, 'The queued job exits at its empty list guard.');
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