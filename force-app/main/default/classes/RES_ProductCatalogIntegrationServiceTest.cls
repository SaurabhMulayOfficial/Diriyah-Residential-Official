/**
 * @description Unit tests for RES_ProductCatalogIntegrationService.
 *
 *              Covers:
 *              - hydrateProductCatalogBody (single / multiple / empty input)
 *              - hydrateProductCatalogBody with child measurements (I vs U indicator, none linked)
 *              - syncProductCatalogs end-to-end (success response / blank response)
 *              - syncProductCatalogs stamps RES_Last_Sync_DateTime__c on the child measurements
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
        RES_Config_Switch__c cfg = RES_Config_Switch__c.getOrgDefaults();
        Boolean wasOff = cfg.RES_Triggers_Off__c;
        cfg.RES_Triggers_Off__c = true;
        upsert cfg;
        ProductCatalog pc = new ProductCatalog(
            Name = 'Integration Test Catalog',
            RES_Name_AR__c = 'Test Arabic Name',
            RES_Master_Plan__c = 'Test Master Plan'
        );
        insert pc;
        cfg.RES_Triggers_Off__c = wasOff;
        upsert cfg;
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
        RES_IntegrationRequestEventService.batchSubmitter =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        ProductCatalog pc1 = buildCatalog();
        RES_Config_Switch__c cfg2 = RES_Config_Switch__c.getOrgDefaults();
        cfg2.RES_Triggers_Off__c = true;
        upsert cfg2;
        ProductCatalog pc2 = new ProductCatalog(Name = 'Second Test Catalog');
        insert pc2;
        cfg2.RES_Triggers_Off__c = false;
        upsert cfg2;

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
        Assert.isTrue(body.contains('RES_Master_Plan'), 'Custom field RES_Master_Plan should be in body');
    }

    // ------------------------------------------------------------------
    // hydrateProductCatalogBody — child measurements
    // ------------------------------------------------------------------

    @IsTest
    static void hydrateBody_withMeasurements_neverSyncedAreInsert() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        RES_IntegrationRequestEventService.batchSubmitter =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        ProductCatalog catalog = buildCatalog();
        RES_IntegrationTestDataFactory.createMeasurementsForCatalog(catalog.Id, 2);

        Test.startTest();
        String body = RES_ProductCatalogIntegrationService.hydrateProductCatalogBody(
            new List<ProductCatalog>{ catalog }, 'I'
        );
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        List<Object> children = (List<Object>) parsed.get('RES_Measurements');
        Assert.areEqual(2, children.size(), 'Both measurements of the catalog should be sent as children');
        for (Object o : children) {
            Assert.areEqual('I', ((Map<String, Object>) o).get('Measurement_Change_Indicator'), 'Never-synced measurement is an insert');
        }
        Assert.areEqual(2, RES_ProductCatalogIntegrationService.includedMeasurementIds.size());
    }

    @IsTest
    static void hydrateBody_withMeasurements_syncedAreUpdate() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        RES_IntegrationRequestEventService.batchSubmitter =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        ProductCatalog catalog = buildCatalog();
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurementsForCatalog(catalog.Id, 2);
        update new RES_Measurement__c(Id = measurements[0].Id, RES_Last_Sync_DateTime__c = System.now());

        Test.startTest();
        String body = RES_ProductCatalogIntegrationService.hydrateProductCatalogBody(
            new List<ProductCatalog>{ catalog }, 'U'
        );
        Test.stopTest();

        Integer inserts = 0;
        Integer updates = 0;
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        for (Object o : (List<Object>) parsed.get('RES_Measurements')) {
            String ci = (String) ((Map<String, Object>) o).get('Measurement_Change_Indicator');
            if (ci == 'I') inserts++;
            if (ci == 'U') updates++;
        }
        Assert.areEqual(1, inserts, 'The never-synced measurement is an insert');
        Assert.areEqual(1, updates, 'The already-synced measurement is an update');
    }

    @IsTest
    static void hydrateBody_noMeasurements_omitsMeasurementArray() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        ProductCatalog catalog = buildCatalog();

        Test.startTest();
        String body = RES_ProductCatalogIntegrationService.hydrateProductCatalogBody(
            new List<ProductCatalog>{ catalog }, 'I'
        );
        Test.stopTest();

        Assert.isFalse(body.contains('RES_Measurements'), 'No measurement array when the catalog has no measurements');
        Assert.isTrue(RES_ProductCatalogIntegrationService.includedMeasurementIds.isEmpty());
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
    // syncProductCatalogs — child measurements stamping
    // ------------------------------------------------------------------

    @IsTest
    static void syncProductCatalogs_successResponse_stampsChildMeasurements() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = successResponseBody();
        Test.setMock(HttpCalloutMock.class, mock);

        ProductCatalog catalog = buildCatalog();
        List<RES_Measurement__c> measurements =
            RES_IntegrationTestDataFactory.createMeasurementsForCatalog(catalog.Id, 2);

        Test.startTest();
        RES_ProductCatalogIntegrationService.syncProductCatalogs(
            new List<ProductCatalog>{ catalog }, REQUEST_METHOD, 'I'
        );
        Test.stopTest();

        Assert.areEqual(1, mock.businessCallCount, 'One business callout should be made');
        for (RES_Measurement__c updated : [
            SELECT RES_Last_Sync_DateTime__c FROM RES_Measurement__c WHERE RES_Catalog__c = :catalog.Id
        ]) {
            Assert.isNotNull(updated.RES_Last_Sync_DateTime__c, 'Last sync datetime should be stamped on success');
        }
    }
}
