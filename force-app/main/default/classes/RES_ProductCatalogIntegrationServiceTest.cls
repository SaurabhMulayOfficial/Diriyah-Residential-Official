/**
 * @description Unit tests for RES_ProductCatalogIntegrationService.
 *
 *              Covers:
 *              - hydrateProductCatalogBody (single / multiple / empty input)
 *              - hydrateCatalogWithMeasurements (happy path / no catalog linked / empty input)
 *              - syncProductCatalogs end-to-end (success response / blank response)
 *              - syncMeasurementsWithProductCatalog end-to-end
 *              - Constructor guard (no API config → exception)
 *
 *              The constructor requires a deployed RES_API_Configuration__mdt record
 *              ('Product_Catalog_API') and a valid SAP token. Tests that need those
 *              return early when the metadata is absent.
 */
@IsTest
private class RES_ProductCatalogIntegrationServiceTest {

    private static final String REQUEST_METHOD = 'GET';

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static Boolean canConstruct() {
        return RES_IntegrationTestDataFactory.hasProductCatalogApiConfiguration(REQUEST_METHOD);
    }

    private static ProductCatalog buildCatalog() {
        ProductCatalog pc = new ProductCatalog(Name = 'Integration Test Catalog');
        insert pc;
        return pc;
    }

    private static String successResponseBody() {
        return JSON.serialize(new Map<String, Object>{
            'Return' => new Map<String, Object>{
                'item' => new List<Object>{
                    new Map<String, Object>{ 'type' => 'S', 'message' => 'Success' }
                }
            }
        });
    }

    private static String errorResponseBody() {
        return JSON.serialize(new Map<String, Object>{
            'Return' => new Map<String, Object>{
                'item' => new List<Object>{
                    new Map<String, Object>{ 'type' => 'E', 'message' => 'SAP error occurred' }
                }
            }
        });
    }

    // ------------------------------------------------------------------
    // hydrateProductCatalogBody
    // ------------------------------------------------------------------

    @IsTest
    static void hydrateBody_singleCatalog_returnsObjectJson() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        ProductCatalog pc = buildCatalog();

        Test.startTest();
        String body = RES_ProductCatalogIntegrationService.hydrateProductCatalogBody(
            new List<ProductCatalog>{ pc }, 'I'
        );
        Test.stopTest();

        Assert.isTrue(String.isNotBlank(body), 'Body should not be blank for a single catalog');
        // Single catalog is serialised as an object, not an array
        Assert.isTrue(body.startsWith('{'), 'Single catalog body should be a JSON object');
        Assert.isTrue(body.contains('Integration Test Catalog'), 'Body should contain the catalog name');
        Assert.isTrue(body.contains('"Change_Indicator"'), 'Body should contain Change_Indicator field');
    }

    @IsTest
    static void hydrateBody_multipleCatalogs_returnsArrayJson() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        ProductCatalog pc1 = buildCatalog();
        ProductCatalog pc2 = new ProductCatalog(Name = 'Second Test Catalog');
        insert pc2;

        Test.startTest();
        String body = RES_ProductCatalogIntegrationService.hydrateProductCatalogBody(
            new List<ProductCatalog>{ pc1, pc2 }, 'U'
        );
        Test.stopTest();

        Assert.isTrue(body.startsWith('['), 'Multiple catalogs body should be a JSON array');
    }

    @IsTest
    static void hydrateBody_nullInput_throwsIntegrationException() {
        Boolean threw = false;
        try {
            RES_ProductCatalogIntegrationService.hydrateProductCatalogBody(null, 'I');
        } catch (RES_IntegrationException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Null input should throw RES_IntegrationException');
    }

    @IsTest
    static void hydrateBody_emptyList_throwsIntegrationException() {
        Boolean threw = false;
        try {
            RES_ProductCatalogIntegrationService.hydrateProductCatalogBody(
                new List<ProductCatalog>(), 'I'
            );
        } catch (RES_IntegrationException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Empty catalog list should throw RES_IntegrationException');
    }

    @IsTest
    static void hydrateBody_customFieldsAreIncluded() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        ProductCatalog pc = buildCatalog();

        Test.startTest();
        String body = RES_ProductCatalogIntegrationService.hydrateProductCatalogBody(
            new List<ProductCatalog>{ pc }, 'I'
        );
        Test.stopTest();

        Assert.isTrue(body.contains('RES_Name_AR'), 'Custom field RES_Name_AR should be in body');
        Assert.isTrue(body.contains('RES_Geo_Latitude'), 'Custom field RES_Geo_Latitude should be in body');
        Assert.isTrue(body.contains('RES_Geo_Longitude'), 'Custom field RES_Geo_Longitude should be in body');
        Assert.isTrue(body.contains('RES_Master_Plan'), 'Custom field RES_Master_Plan should be in body');
    }

    // ------------------------------------------------------------------
    // hydrateCatalogWithMeasurements
    // ------------------------------------------------------------------

    @IsTest
    static void hydrateMeasurements_happyPath_returnsCatalogWithMeasurements() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        ProductCatalog catalog = buildCatalog();
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurementsForCatalog(catalog.Id, 2);

        Test.startTest();
        String body = RES_ProductCatalogIntegrationService.hydrateCatalogWithMeasurements(
            measurements, 'I'
        );
        Test.stopTest();

        Assert.isTrue(String.isNotBlank(body), 'Body should not be blank');
        Assert.isTrue(
            body.contains('RES_Measurements') || body.contains('Measurement_Change_Indicator'),
            'Body should contain measurement data'
        );
    }

    @IsTest
    static void hydrateMeasurements_noCatalogLinked_throwsIntegrationException() {
        RES_Measurement__c m = new RES_Measurement__c(
            RES_Measurement_Type__c   = 'Z002',
            RES_Measurement_Amount__c = 100
        );
        // RES_Catalog__c intentionally left null
        // We don't insert to avoid required field errors; pass uninserted with null catalog
        List<ProductCategory> cats = RES_IntegrationTestDataFactory.createCategories(1, false);
        m.RES_Category__c = cats[0].Id;
        insert m;

        Boolean threw = false;
        try {
            RES_ProductCatalogIntegrationService.hydrateCatalogWithMeasurements(
                new List<RES_Measurement__c>{ m }, 'I'
            );
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('No Product Catalog Associated'),
                'Exception should mention missing catalog association'
            );
        }
        Assert.isTrue(threw, 'Measurement without RES_Catalog__c should throw RES_IntegrationException');
    }

    @IsTest
    static void hydrateMeasurements_multipleCatalogs_returnsArray() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        ProductCatalog cat1 = buildCatalog();
        ProductCatalog cat2 = new ProductCatalog(Name = 'Second Catalog For Measurement');
        insert cat2;

        List<RES_Measurement__c> m1 =
            RES_IntegrationTestDataFactory.createMeasurementsForCatalog(cat1.Id, 1);
        List<RES_Measurement__c> m2 =
            RES_IntegrationTestDataFactory.createMeasurementsForCatalog(cat2.Id, 1);

        List<RES_Measurement__c> combined = new List<RES_Measurement__c>();
        combined.addAll(m1);
        combined.addAll(m2);

        Test.startTest();
        String body = RES_ProductCatalogIntegrationService.hydrateCatalogWithMeasurements(
            combined, 'U'
        );
        Test.stopTest();

        Assert.isTrue(body.startsWith('['), 'Multiple catalogs should produce a JSON array');
    }

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    @IsTest
    static void constructor_noApiConfig_throwsIntegrationException() {
        if (canConstruct()) { return; }

        Boolean threw = false;
        try {
            new RES_ProductCatalogIntegrationService(REQUEST_METHOD);
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('No API configuration'),
                'Exception should mention missing API configuration'
            );
        }
        Assert.isTrue(threw, 'Missing API config should raise RES_IntegrationException');
    }

    // ------------------------------------------------------------------
    // syncProductCatalogs — end-to-end
    // ------------------------------------------------------------------

    @IsTest
    static void syncProductCatalogs_successResponse_updatesLastSyncDateTime() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = successResponseBody();
        Test.setMock(HttpCalloutMock.class, mock);

        ProductCatalog catalog = buildCatalog();

        Test.startTest();
        RES_ProductCatalogIntegrationService.syncProductCatalogs(
            new List<ProductCatalog>{ catalog }, REQUEST_METHOD, 'I'
        );
        Test.stopTest();

        Assert.areEqual(1, mock.businessCallCount, 'One business callout should be made');
        ProductCatalog updated = [
            SELECT RES_Last_Sync_DateTime__c FROM ProductCatalog WHERE Id = :catalog.Id
        ];
        Assert.isNotNull(updated.RES_Last_Sync_DateTime__c, 'Last sync datetime should be stamped on success');
    }

    @IsTest
    static void syncProductCatalogs_errorResponse_doesNotUpdateLastSync() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = errorResponseBody();
        Test.setMock(HttpCalloutMock.class, mock);

        ProductCatalog catalog = buildCatalog();

        Test.startTest();
        RES_ProductCatalogIntegrationService.syncProductCatalogs(
            new List<ProductCatalog>{ catalog }, REQUEST_METHOD, 'I'
        );
        Test.stopTest();

        ProductCatalog unchanged = [
            SELECT RES_Last_Sync_DateTime__c FROM ProductCatalog WHERE Id = :catalog.Id
        ];
        Assert.isNull(unchanged.RES_Last_Sync_DateTime__c, 'Last sync datetime should NOT be set on SAP error');
    }

    @IsTest
    static void syncProductCatalogs_blankResponseBody_doesNotThrow() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = '';
        Test.setMock(HttpCalloutMock.class, mock);

        ProductCatalog catalog = buildCatalog();

        Boolean threw = false;
        Test.startTest();
        try {
            RES_ProductCatalogIntegrationService.syncProductCatalogs(
                new List<ProductCatalog>{ catalog }, REQUEST_METHOD, 'I'
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'A blank response body should be handled gracefully');
    }

    @IsTest
    static void syncProductCatalogs_calloutException_doesNotPropagate() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.throwOnBusiness = true;
        Test.setMock(HttpCalloutMock.class, mock);

        ProductCatalog catalog = buildCatalog();

        Boolean threw = false;
        Test.startTest();
        try {
            RES_ProductCatalogIntegrationService.syncProductCatalogs(
                new List<ProductCatalog>{ catalog }, REQUEST_METHOD, 'I'
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'Callout exception inside syncProductCatalogs should be caught internally');
    }

    // ------------------------------------------------------------------
    // syncMeasurementsWithProductCatalog — end-to-end
    // ------------------------------------------------------------------

    @IsTest
    static void syncMeasurementsWithCatalog_successResponse_updatesLastSyncDateTime() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = successResponseBody();
        Test.setMock(HttpCalloutMock.class, mock);

        ProductCatalog catalog = buildCatalog();
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurementsForCatalog(catalog.Id, 1);

        Test.startTest();
        RES_ProductCatalogIntegrationService.syncMeasurementsWithProductCatalog(
            measurements, REQUEST_METHOD, 'I'
        );
        Test.stopTest();

        Assert.areEqual(1, mock.businessCallCount, 'One business callout should be made');
        RES_Measurement__c updated = [
            SELECT RES_Last_Sync_DateTime__c FROM RES_Measurement__c WHERE Id = :measurements[0].Id
        ];
        Assert.isNotNull(updated.RES_Last_Sync_DateTime__c, 'Last sync datetime should be stamped on success');
    }

    @IsTest
    static void syncMeasurementsWithCatalog_calloutException_doesNotPropagate() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.throwOnBusiness = true;
        Test.setMock(HttpCalloutMock.class, mock);

        ProductCatalog catalog = buildCatalog();
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurementsForCatalog(catalog.Id, 1);

        Boolean threw = false;
        Test.startTest();
        try {
            RES_ProductCatalogIntegrationService.syncMeasurementsWithProductCatalog(
                measurements, REQUEST_METHOD, 'I'
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'Callout exception inside syncMeasurementsWithProductCatalog should be caught');
    }
}
