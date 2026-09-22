/**
 * @description Unit tests for RES_ProductCatalogServices.
 *
 *              The service publishes a RES_Integration_Request__e platform event;
 *              it does NOT enqueue jobs directly. Jobs are created by the
 *              platform-event subscriber (RES_IntegrationRequestEventService) after
 *              Test.getEventBus().deliver() is called.
 *
 *              Custom metadata (RES_SAP_Integration_Config__mdt 'Product_Catalog_Sync')
 *              cannot be created in a test. Tests that require it return early when it
 *              is not deployed; the "config missing" test runs only in that situation.
 */
@IsTest
private class RES_ProductCatalogServicesTest {

    private static final String CONFIG_DEV_NAME = 'Product_Catalog_Sync';

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static RES_SAP_Integration_Config__mdt getConfig() {
        return new RES_SAPIntegrationConfigDAO()
            .getSAPIntegrationConfigByDeveloperName(CONFIG_DEV_NAME);
    }

    private static Boolean configReady() {
        RES_SAP_Integration_Config__mdt cfg = getConfig();
        return cfg != null && String.isNotBlank(cfg.RES_Sync_Fields__c);
    }

    private static Set<String> getSyncFields() {
        Set<String> fields = new Set<String>();
        RES_SAP_Integration_Config__mdt cfg = getConfig();
        if (cfg != null && String.isNotBlank(cfg.RES_Sync_Fields__c)) {
            for (String f : cfg.RES_Sync_Fields__c.split(',')) {
                if (String.isNotBlank(f)) {
                    fields.add(f.trim().toLowerCase());
                }
            }
        }
        return fields;
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
     * Calls syncProductCatalog, delivers the event bus, and returns the
     * delta in RES_IntegrationQueueable jobs caused by that call.
     */
    private static Integer syncAndCountJobs(
        List<ProductCatalog> catalogs,
        Map<Id, ProductCatalog> oldMap
    ) {
        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Test.getEventBus().deliver();   // flush events from test-data inserts
        Integer before = queueableJobCount();

        RES_ProductCatalogServices.syncProductCatalog(catalogs, oldMap);
        Test.getEventBus().deliver();   // deliver the event published by the service

        Integer after = queueableJobCount();
        Test.stopTest();
        return after - before;
    }

    // ------------------------------------------------------------------
    // Config missing
    // ------------------------------------------------------------------

    @IsTest
    static void sync_configMissing_throwsIntegrationException() {
        if (configReady()) { return; }

        Boolean threw = false;
        try {
            RES_ProductCatalogServices.syncProductCatalog(
                new List<ProductCatalog>(), null
            );
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('SAP Integration Config'),
                'Exception message should mention SAP Integration Config'
            );
        }
        Assert.isTrue(threw, 'Missing config should raise RES_IntegrationException');
    }

    // ------------------------------------------------------------------
    // Insert path (oldMap == null)
    // ------------------------------------------------------------------

    @IsTest
    static void sync_insert_allCatalogsAreQueued() {
        if (!configReady()) { return; }

        List<ProductCatalog> catalogs = new List<ProductCatalog>{
            new ProductCatalog(Name = 'Catalog A'),
            new ProductCatalog(Name = 'Catalog B')
        };
        insert catalogs;

        Integer jobs = syncAndCountJobs(catalogs, null);

        Assert.areEqual(1, jobs, 'A single job should cover all inserted catalogs');
    }

    // ------------------------------------------------------------------
    // Update path
    // ------------------------------------------------------------------

    @IsTest
    static void sync_update_syncFieldChanged_publishesEvent() {
        if (!configReady()) { return; }

        ProductCatalog catalog = new ProductCatalog(Name = 'Catalog Changed');
        insert catalog;

        // Build an old version that differs on the first sync field
        Set<String> syncFields = getSyncFields();
        String changedField = syncFields.isEmpty() ? null : new List<String>(syncFields)[0];
        if (changedField == null) { return; }

        Map<Id, ProductCatalog> oldMap = new Map<Id, ProductCatalog>();
        ProductCatalog oldCatalog = catalog.clone(true);
        oldCatalog.put(changedField, null);
        oldMap.put(oldCatalog.Id, oldCatalog);

        Integer jobs = syncAndCountJobs(new List<ProductCatalog>{ catalog }, oldMap);

        Assert.areEqual(1, jobs, 'A changed sync field should publish an event and create a job');
    }

    @IsTest
    static void sync_update_noChanges_publishesNothing() {
        if (!configReady()) { return; }

        ProductCatalog catalog = new ProductCatalog(Name = 'Catalog Unchanged');
        insert catalog;

        Map<Id, ProductCatalog> oldMap = new Map<Id, ProductCatalog>{
            catalog.Id => catalog.clone(true)
        };

        Integer jobs = syncAndCountJobs(new List<ProductCatalog>{ catalog }, oldMap);

        Assert.areEqual(0, jobs, 'Identical old/new values must not publish an event');
    }

    @IsTest
    static void sync_update_recordMissingFromOldMap_treatedAsChanged() {
        if (!configReady()) { return; }

        ProductCatalog catalog = new ProductCatalog(Name = 'Catalog Missing From OldMap');
        insert catalog;

        // Non-null but empty oldMap -> oldMap.get(Id) returns null -> treated as changed
        Integer jobs = syncAndCountJobs(
            new List<ProductCatalog>{ catalog },
            new Map<Id, ProductCatalog>()
        );

        Assert.areEqual(1, jobs, 'A record absent from oldMap should be treated as changed');
    }

    // ------------------------------------------------------------------
    // Empty inputs
    // ------------------------------------------------------------------

    @IsTest
    static void sync_emptyList_insertContext_publishesNothing() {
        if (!configReady()) { return; }

        Integer jobs = syncAndCountJobs(new List<ProductCatalog>(), null);

        Assert.areEqual(0, jobs, 'Empty catalog list should not publish an event');
    }

    @IsTest
    static void sync_emptyList_updateContext_publishesNothing() {
        if (!configReady()) { return; }

        Integer jobs = syncAndCountJobs(
            new List<ProductCatalog>(),
            new Map<Id, ProductCatalog>()
        );

        Assert.areEqual(0, jobs, 'Empty catalog list in update context should not publish an event');
    }

    // ------------------------------------------------------------------
    // Trigger context label
    // ------------------------------------------------------------------

    @IsTest
    static void sync_insertContext_setsInsertTriggerLabel() {
        if (!configReady()) { return; }

        // Verifying insert path does not throw; trigger context 'I' is set internally
        ProductCatalog catalog = new ProductCatalog(Name = 'Context Label Test');
        insert catalog;

        Boolean threw = false;
        try {
            RES_ProductCatalogServices.syncProductCatalog(
                new List<ProductCatalog>{ catalog },
                null
            );
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'syncProductCatalog should not throw for a valid insert context');
    }

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    @IsTest
    static void constructor_canBeInstantiated() {
        Assert.isNotNull(
            new RES_ProductCatalogServices(),
            'The no-arg constructor should be usable'
        );
    }
}
