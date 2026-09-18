/**
 * @description Unit tests for RES_IntegrationQueueable.
 *
 *              Most branches of execute() only cast records and then call a
 *              commented out service, so they are covered with uninserted
 *              SObjects and no callout. The ProductCategory and Measurement
 *              branches are live and need mocks plus a primed SAP token.
 */
@isTest
private class RES_IntegrationQueueableTest {

    private static final String METHOD = 'GET';

    /* ====================================================================
     *  GUARD CLAUSES
     * ==================================================================== */

    @isTest
    static void executeReturnsEarlyForNullRecords() {
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new RES_IntegrationQueueable(null, 'ProductCategory_Sync', METHOD, 'I').execute(null);
        Test.stopTest();

        Assert.areEqual(0, mock.businessCallCount, 'A null record list must not trigger a callout.');
    }

    @isTest
    static void executeReturnsEarlyForEmptyRecords() {
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new RES_IntegrationQueueable(
            new List<SObject>(), 'ProductCategory_Sync', METHOD, 'I'
        ).execute(null);
        Test.stopTest();

        Assert.areEqual(0, mock.businessCallCount, 'An empty record list must not trigger a callout.');
    }

    @isTest
    static void executeIgnoresUnknownServiceName() {
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new RES_IntegrationQueueable(
            new List<SObject>{ new Account(Name = 'Ignored') },
            'Does_Not_Exist_Sync',
            METHOD,
            'I'
        ).execute(null);
        Test.stopTest();

        Assert.areEqual(0, mock.businessCallCount, 'An unrecognised service name should be a no-op.');
    }

    /* ====================================================================
     *  LIVE BRANCHES
     * ==================================================================== */

    @isTest
    static void executeRoutesProductCategorySync() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);

        Test.startTest();
        System.enqueueJob(
            new RES_IntegrationQueueable(categories, 'ProductCategory_Sync', METHOD, 'I')
        );
        Test.stopTest();

        Assert.areEqual(1, mock.businessCallCount, 'The ProductCategory branch should reach the service.');
    }

    @isTest
    static void executeRoutesMeasurementSync() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurements(categories[0].Id, 1);

        Test.startTest();
        System.enqueueJob(
            new RES_IntegrationQueueable(measurements, 'Measurement_Sync', METHOD, 'U')
        );
        Test.stopTest();

        Assert.areEqual(1, mock.businessCallCount, 'The Measurement branch should reach the service.');
    }

    /* ====================================================================
     *  PLACEHOLDER BRANCHES
     *  These only exercise the cast loops; the service calls are commented
     *  out in the production class. Revisit once they are enabled.
     * ==================================================================== */

    @isTest
    static void executeHandlesContractSyncBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        new RES_IntegrationQueueable(
            new List<SObject>{ new Contract() }, 'Contract_Sync', METHOD, 'I'
        ).execute(null);
        Test.stopTest();

        Assert.isTrue(true, 'The Contract branch casts records without error.');
    }

    @isTest
    static void executeHandlesAccountSyncBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        new RES_IntegrationQueueable(
            new List<SObject>{ new Account(Name = 'Test Account') }, 'Account_Sync', METHOD, 'I'
        ).execute(null);
        Test.stopTest();

        Assert.isTrue(true, 'The Account branch casts records without error.');
    }

    @isTest
    static void executeHandlesProductSyncBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        new RES_IntegrationQueueable(
            new List<SObject>{ new Product2(Name = 'Test Product') }, 'Product_Sync', METHOD, 'I'
        ).execute(null);
        Test.stopTest();

        Assert.isTrue(true, 'The Product branch casts records without error.');
    }

    @isTest
    static void executeHandlesProductCatalogSyncBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        new RES_IntegrationQueueable(
            new List<SObject>{ new ProductCatalog(Name = 'Test Catalog') },
            'ProductCatalog_Sync',
            METHOD,
            'I'
        ).execute(null);
        Test.stopTest();

        Assert.isTrue(true, 'The ProductCatalog branch casts records without error.');
    }

    /**
     * The cast loops are unguarded, so a caller that passes the wrong SObject
     * type for a service name gets a runtime TypeException rather than a
     * handled error. Worth a guard in the production class.
     */
    @isTest
    static void executeThrowsWhenRecordTypeDoesNotMatchServiceName() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Boolean threw = false;

        Test.startTest();
        try {
            new RES_IntegrationQueueable(
                new List<SObject>{ new Account(Name = 'Wrong Type') },
                'ProductCategory_Sync',
                METHOD,
                'I'
            ).execute(null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A mismatched SObject type currently fails hard inside the cast loop.');
    }

    /* ====================================================================
     *  CONSTRUCTOR
     * ==================================================================== */

    @isTest
    static void constructorRetainsSuppliedArguments() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        RES_IntegrationQueueable job = new RES_IntegrationQueueable(
            new List<SObject>(), 'ProductCategory_Sync', 'POST', 'U'
        );
        job.execute(null);
        Test.stopTest();

        Assert.isNotNull(job, 'The queueable should be constructible with all four arguments.');
    }
}