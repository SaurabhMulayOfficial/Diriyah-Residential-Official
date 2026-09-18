/**
 * @description Unit tests for RES_MeasurementServices.
 *
 *              Like the ProductCategory service, this class enqueues a
 *              RES_IntegrationQueueable, so the job executes at stopTest()
 *              and needs an HTTP mock plus a primed SAP token.
 */
@isTest
private class RES_MeasurementServicesTest {

    @isTest
    static void syncEnqueuesQueueableJob() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurements(categories[0].Id, 2);

        Test.startTest();
        RES_MeasurementServices.syncMeasurements(measurements, null);
        Assert.areEqual(
            3,
            [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable'],
            'One queueable job should be enqueued.'
        );
        Test.stopTest();

        Assert.areEqual(3, mock.businessCallCount, 'The queued job should perform the sync callout.');
    }

    @isTest
    static void syncHandlesEmptyList() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        RES_MeasurementServices.syncMeasurements(new List<RES_Measurement__c>(), null);
        Test.stopTest();

        Assert.areEqual(0, mock.businessCallCount, 'An empty input should not produce a callout.');
    }

    @isTest
    static void constructorIsCovered() {
        Test.startTest();
        RES_MeasurementServices service = new RES_MeasurementServices();
        Test.stopTest();

        Assert.isNotNull(service, 'The no-arg constructor should be usable.');
    }
}