/**
 * @description Unit tests for RES_ProductCategoryIntegrationService.
 *
 *              PREREQUISITE: RES_API_Configuration__mdt records cannot be
 *              created in an Apex test. The tests below require deployed
 *              configuration for DeveloperName-style lookup
 *              ('GET' / 'Building_Land_API' and 'POST' / 'Building_Land_API').
 *              If those records are missing the constructor throws and the
 *              affected tests fail with RES_IntegrationException.
 *
 *              The cleanest fix is a @TestVisible injection point on the
 *              service for the DAO, which would remove this dependency.
 */
@isTest
private class RES_ProductCategoryServiceTest {

    private static final String METHOD = 'GET';

    /* ====================================================================
     *  CONSTRUCTOR
     * ==================================================================== */

    @isTest
    static void constructorSucceedsWithValidConfigurationAndToken() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        RES_ProductCategoryIntegrationService service =
            new RES_ProductCategoryIntegrationService(METHOD);
        Test.stopTest();

        Assert.isNotNull(service, 'The service should be constructed when config and token are available.');
    }

    @isTest
    static void constructorThrowsWhenNoApiConfigurationExists() {
        RES_IntegrationTestDataFactory.primeSapToken();

        Boolean threw = false;
        String message;

        Test.startTest();
        try {
            // A verb that will never be configured for Building_Land_API.
            new RES_ProductCategoryIntegrationService('TRACE');
        } catch (RES_IntegrationException e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A missing configuration should raise RES_IntegrationException.');
        Assert.isTrue(
            message.contains('No API configuration found'),
            'The exception should explain that configuration is missing.'
        );
    }

    @isTest
    static void constructorThrowsWhenSapTokenIsBlank() {
        RES_IntegrationTestDataFactory.clearSapToken();

        // Token callout returns 200 but without an access_token key,
        // so the provider hands back a blank token.
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.tokenBody = '{"token_type":"Bearer"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Boolean threw = false;
        String message;

        Test.startTest();
        try {
            new RES_ProductCategoryIntegrationService(METHOD);
        } catch (RES_IntegrationException e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A blank token should raise RES_IntegrationException.');
        Assert.isTrue(
            message.contains('Failed to retrieve SAP token'),
            'The exception should explain that the token could not be retrieved.'
        );
    }

    @isTest
    static void constructorAppliesAuthorizationHeader() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);

        Test.startTest();
        RES_ProductCategoryIntegrationService.syncProductCategories(categories, METHOD, 'I');
        Test.stopTest();

        Assert.areEqual(1, mock.businessCallCount, 'One business callout should have been made.');
        Assert.areEqual(
            'Bearer ' + RES_IntegrationTestDataFactory.MOCK_ACCESS_TOKEN,
            mock.businessRequests[0].getHeader('Authorization'),
            'The bearer token should be attached to the outbound request.'
        );
    }

    /* ====================================================================
     *  hydrateRequestBody  (ProductCategory)
     * ==================================================================== */

    @isTest
    static void hydrateRequestBodySerialisesSingleRecordAsObject() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);

        Test.startTest();
        RES_ProductCategoryIntegrationService service =
            new RES_ProductCategoryIntegrationService(METHOD);
        String body = service.hydrateRequestBody(categories, 'I');
        Test.stopTest();

        Assert.isTrue(body.startsWith('{'), 'A single record should serialise as a JSON object, not an array.');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Assert.areEqual('Test Category 0', parsed.get('Name'), 'Name should be mapped onto the wrapper.');
        Assert.areEqual('1000', parsed.get('RES_Company_Code'), 'Company code should be mapped.');
        Assert.areEqual('BE-001', parsed.get('RES_Business_Entity_Id'), 'Business entity id should be mapped.');
        Assert.areEqual('PROP-0', parsed.get('RES_Property_ID'), 'Property id should be mapped.');
        Assert.areEqual('PC-100', parsed.get('RES_Profit_Center'), 'Profit center should be mapped.');
        Assert.areEqual('Land', parsed.get('RES_Property_Type'), 'Property type should be mapped.');
        Assert.areEqual('I', parsed.get('Change_Indicator'), 'The trigger context drives the change indicator.');
    }

    @isTest
    static void hydrateRequestBodySerialisesMultipleRecordsAsArray() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(3, true);

        Test.startTest();
        RES_ProductCategoryIntegrationService service =
            new RES_ProductCategoryIntegrationService(METHOD);
        String body = service.hydrateRequestBody(categories, 'U');
        Test.stopTest();

        Assert.isTrue(body.startsWith('['), 'Multiple records should serialise as a JSON array.');

        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(body);
        Assert.areEqual(3, parsed.size(), 'Every supplied record should appear in the payload.');

        Map<String, Object> first = (Map<String, Object>) parsed[0];
        Assert.areEqual('U', first.get('Change_Indicator'), 'The update indicator should be propagated.');
    }

    @isTest
    static void hydrateRequestBodyThrowsOnNullList() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Boolean threw = false;

        Test.startTest();
        RES_ProductCategoryIntegrationService service =
            new RES_ProductCategoryIntegrationService(METHOD);
        try {
            service.hydrateRequestBody(null, 'I');
        } catch (RES_IntegrationException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A null record list should raise RES_IntegrationException.');
    }

    @isTest
    static void hydrateRequestBodyThrowsOnEmptyList() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Boolean threw = false;

        Test.startTest();
        RES_ProductCategoryIntegrationService service =
            new RES_ProductCategoryIntegrationService(METHOD);
        try {
            service.hydrateRequestBody(new List<ProductCategory>(), 'I');
        } catch (RES_IntegrationException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'An empty record list should raise RES_IntegrationException.');
    }

    /* ====================================================================
     *  hydrateRequestBodyForMeasurements
     * ==================================================================== */

    @isTest
    static void hydrateMeasurementsGroupsByCategory() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurements(categories[0].Id, 3);

        Test.startTest();
        RES_ProductCategoryIntegrationService service =
            new RES_ProductCategoryIntegrationService(METHOD);
        String body = service.hydrateRequestBodyForMeasurements(measurements, 'I');
        Test.stopTest();

        Assert.isTrue(body.startsWith('{'), 'Three measurements on one category collapse to a single wrapper.');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Assert.areEqual('U', parsed.get('Change_Indicator'),
            'The category indicator is hard coded to U on the measurement path.');

        List<Object> nested = (List<Object>) parsed.get('RES_Measurements');
        Assert.areEqual(3, nested.size(), 'All three measurements should be nested under the category.');

        Map<String, Object> firstMeasurement = (Map<String, Object>) nested[0];
        Assert.areEqual('I', firstMeasurement.get('Measurement_Change_Indicator'),
            'The trigger context drives the measurement level indicator.');
        Assert.areEqual(125.50, firstMeasurement.get('RES_Measurement_Amount'),
            'The measurement amount should be mapped onto the wrapper.');
    }

    @isTest
    static void hydrateMeasurementsProducesArrayForMultipleCategories() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(2, true);
        List<RES_Measurement__c> measurements = new List<RES_Measurement__c>{
            RES_IntegrationTestDataFactory.buildMeasurement(categories[0].Id, 'Area'),
            RES_IntegrationTestDataFactory.buildMeasurement(categories[1].Id, 'Volume')
        };
        insert measurements;

        Test.startTest();
        RES_ProductCategoryIntegrationService service =
            new RES_ProductCategoryIntegrationService(METHOD);
        String body = service.hydrateRequestBodyForMeasurements(measurements, 'U');
        Test.stopTest();

        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(body);
        Assert.areEqual(2, parsed.size(), 'Each distinct category should produce its own wrapper.');
    }

    @isTest
    static void hydrateMeasurementsThrowsOnNullList() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Boolean threw = false;

        Test.startTest();
        RES_ProductCategoryIntegrationService service =
            new RES_ProductCategoryIntegrationService(METHOD);
        try {
            service.hydrateRequestBodyForMeasurements(null, 'I');
        } catch (RES_IntegrationException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A null measurement list should raise RES_IntegrationException.');
    }

    @isTest
    static void hydrateMeasurementsThrowsOnEmptyList() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Boolean threw = false;

        Test.startTest();
        RES_ProductCategoryIntegrationService service =
            new RES_ProductCategoryIntegrationService(METHOD);
        try {
            service.hydrateRequestBodyForMeasurements(new List<RES_Measurement__c>(), 'I');
        } catch (RES_IntegrationException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'An empty measurement list should raise RES_IntegrationException.');
    }

    @isTest
    static void hydrateMeasurementsThrowsWhenNoMeasurementHasACategory() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        // Measurements with a null lookup never reach the wrapper list.
        List<RES_Measurement__c> orphans = new List<RES_Measurement__c>{
            RES_IntegrationTestDataFactory.buildMeasurement(null, 'Area'),
            RES_IntegrationTestDataFactory.buildMeasurement(null, 'Volume')
        };

        Boolean threw = false;
        String message;

        Test.startTest();
        RES_ProductCategoryIntegrationService service =
            new RES_ProductCategoryIntegrationService(METHOD);
        try {
            service.hydrateRequestBodyForMeasurements(orphans, 'I');
        } catch (RES_IntegrationException e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Measurements without a category produce an empty payload and should throw.');
        Assert.isTrue(
            message.contains('Empty Request Body'),
            'The empty payload branch should be the one that fires.'
        );
    }

    /* ====================================================================
     *  syncProductCategories
     * ==================================================================== */

    @isTest
    static void syncProductCategoriesStampsLastSyncOnSuccess() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(2, true);

        Test.startTest();
        RES_ProductCategoryIntegrationService.syncProductCategories(categories, METHOD, 'I');
        Test.stopTest();

        Assert.areEqual(1, mock.businessCallCount, 'One callout should carry the whole batch.');

        List<ProductCategory> refreshed = [
            SELECT Id, RES_Last_Sync_DateTime__c
            FROM ProductCategory
            WHERE Id IN :categories
        ];
        for (ProductCategory pc : refreshed) {
            Assert.isNotNull(pc.RES_Last_Sync_DateTime__c, 'A successful sync should stamp the sync timestamp.');
        }
    }

    @isTest
    static void syncProductCategoriesSendsSerialisedPayload() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);

        Test.startTest();
        RES_ProductCategoryIntegrationService.syncProductCategories(categories, METHOD, 'I');
        Test.stopTest();

        String sentBody = mock.lastBusinessBody();
        Assert.isNotNull(sentBody, 'The hydrated body should be attached to the request.');
        Assert.isTrue(sentBody.contains('PROP-0'), 'The payload should contain the category property id.');
    }

    /**
     * Documents current behaviour. sendRequest() returns null on a permanent
     * failure, so the debug line dereferencing response.statusCode throws an
     * NPE that is swallowed by the catch block. The result is that failures
     * are silent AND the sync timestamp is never written, which is at least
     * directionally correct but happens by accident rather than by design.
     */
    @isTest
    static void syncProductCategoriesSwallowsFailureAndSkipsTimestamp() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessStatusCode = 500;
        mock.businessStatus = 'Internal Server Error';
        mock.businessBody = '{"error":"boom"}';
        Test.setMock(HttpCalloutMock.class, mock);

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);

        Test.startTest();
        RES_ProductCategoryIntegrationService.syncProductCategories(categories, METHOD, 'I');
        Test.stopTest();

        List<ProductCategory> refreshed = [
            SELECT Id, RES_Last_Sync_DateTime__c
            FROM ProductCategory
            WHERE Id IN :categories
        ];
        Assert.isNull(
            refreshed[0].RES_Last_Sync_DateTime__c,
            'A failed callout should not stamp the record as synced.'
        );

        List<RES_Integration_Log__c> logs = [SELECT Id, RES_Type_of_Failure__c FROM RES_Integration_Log__c];
        Assert.areEqual(1, logs.size(), 'The base class should have logged the failure.');
        Assert.areEqual('Server Side', logs[0].RES_Type_of_Failure__c, 'A 500 is a server side failure.');
    }

    @isTest
    static void syncProductCategoriesPropagatesHydrationException() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Boolean threw = false;

        Test.startTest();
        try {
            // Hydration runs before the try block, so this escapes the method.
            RES_ProductCategoryIntegrationService.syncProductCategories(
                new List<ProductCategory>(), METHOD, 'I'
            );
        } catch (RES_IntegrationException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Hydration failures are not caught by syncProductCategories.');
    }

    /* ====================================================================
     *  syncMeasurements
     * ==================================================================== */

    @isTest
    static void syncMeasurementsStampsLastSyncOnSuccess() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurements(categories[0].Id, 2);

        Test.startTest();
        RES_ProductCategoryIntegrationService.syncMeasurements(measurements, METHOD, 'I');
        Test.stopTest();

        Assert.areEqual(1, mock.businessCallCount, 'One callout should carry the measurement batch.');

        List<RES_Measurement__c> refreshed = [
            SELECT Id, RES_Last_Sync_DateTime__c
            FROM RES_Measurement__c
            WHERE Id IN :measurements
        ];
        for (RES_Measurement__c m : refreshed) {
            Assert.isNotNull(m.RES_Last_Sync_DateTime__c, 'A successful sync should stamp the sync timestamp.');
        }
    }

    @isTest
    static void syncMeasurementsSwallowsFailureAndSkipsTimestamp() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessStatusCode = 404;
        mock.businessStatus = 'Not Found';
        mock.businessBody = '{"error":"missing"}';
        Test.setMock(HttpCalloutMock.class, mock);

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurements(categories[0].Id, 1);

        Test.startTest();
        RES_ProductCategoryIntegrationService.syncMeasurements(measurements, METHOD, 'I');
        Test.stopTest();

        List<RES_Measurement__c> refreshed = [
            SELECT Id, RES_Last_Sync_DateTime__c
            FROM RES_Measurement__c
            WHERE Id IN :measurements
        ];
        Assert.isNull(
            refreshed[0].RES_Last_Sync_DateTime__c,
            'A failed callout should not stamp the record as synced.'
        );
        Assert.areEqual(
            'Client Side',
            [SELECT RES_Type_of_Failure__c FROM RES_Integration_Log__c LIMIT 1].RES_Type_of_Failure__c,
            'A 404 is a client side failure.'
        );
    }

    @isTest
    static void syncMeasurementsPropagatesHydrationException() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Boolean threw = false;

        Test.startTest();
        try {
            RES_ProductCategoryIntegrationService.syncMeasurements(null, METHOD, 'I');
        } catch (RES_IntegrationException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Hydration failures are not caught by syncMeasurements.');
    }
}