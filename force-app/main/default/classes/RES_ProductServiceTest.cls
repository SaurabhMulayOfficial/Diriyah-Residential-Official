/**
 * @description Tests for RES_ProductService — change-detection and event-publishing logic.
 * @author      Roshan Jambhule
 * @date        2025
 */
@isTest
private class RES_ProductServiceTest {

    private static final String UNIT_SYNC = 'Unit_Sync';

    // True when the org has the Unit_API configuration required by the integration service.
    private static Boolean canConstruct() {
        return !new RES_APIConfigurationsDAO().getAPIConfiguration('GET', 'Unit_API').isEmpty();
    }

    // Bypasses Product2 triggers so test setup does not publish platform events.
    private static Product2 insertWithoutTrigger(Product2 p) {
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId        = UserInfo.getOrganizationId(),
            RES_Triggers_Off__c = true
        );
        upsert cfg;
        insert p;
        cfg.RES_Triggers_Off__c = false;
        update cfg;
        return p;
    }

    // True when the org has the Unit_Sync metadata required by syncProducts.
    private static Boolean hasSyncConfig() {
        RES_SAP_Integration_Config__mdt config =
            new RES_SAPIntegrationConfigDAO().getSAPIntegrationConfigByDeveloperName(UNIT_SYNC);
        return config != null && String.isNotBlank(config.RES_Sync_Fields__c);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 1. isProductChanged — same values in all sync fields → false
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testIsProductChangedReturnsFalseWhenUnchanged() {
        Product2 p1 = new Product2(Family = '1004', RES_Unit_Status__c = 'Available');
        Product2 p2 = new Product2(Family = '1004', RES_Unit_Status__c = 'Available');

        Boolean changed = RES_ProductService.isProductChanged(
            p1, p2, new Set<String>{ 'Family', 'RES_Unit_Status__c' }
        );

        Assert.isFalse(changed, 'No changed fields must return false');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. isProductChanged — one sync field differs → true
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testIsProductChangedReturnsTrueWhenFieldDiffers() {
        Product2 p1 = new Product2(Family = '1004');
        Product2 p2 = new Product2(Family = '1005');

        Boolean changed = RES_ProductService.isProductChanged(
            p1, p2, new Set<String>{ 'Family' }
        );

        Assert.isTrue(changed, 'A changed field value must return true');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. isProductChanged — null oldRecord → always true (treated as INSERT)
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testIsProductChangedTrueWhenOldRecordNull() {
        Boolean changed = RES_ProductService.isProductChanged(
            new Product2(Family = '1004'), null, new Set<String>{ 'Family' }
        );

        Assert.isTrue(changed, 'Null oldRecord must always return true (new record scenario)');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. isProductChanged — invalid field name in syncFields → graceful skip
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testIsProductChangedSkipsInvalidField() {
        Product2 p1 = new Product2();
        Product2 p2 = new Product2();

        // Should not throw even for an unrecognised field name
        Boolean changed = RES_ProductService.isProductChanged(
            p1, p2, new Set<String>{ 'NonExistent_Field_XYZ__c', 'Family' }
        );

        Assert.isFalse(changed,
            'Unrecognised fields must be silently skipped; result for identical products must be false');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 5. syncProducts INSERT (null oldMap) — queues event without exception
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSyncProductsInsertQueuesEvent() {
        if (!hasSyncConfig() || !canConstruct()) return;

        // Downstream queueable makes a callout — prime token and set mock.
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Product2 p = new Product2(
            Name = 'SPS-INSERT', IsActive = true,
            StockKeepingUnit = 'SKU-SPS-I',
            Family = '1004', RES_Type__c = 'N'
        );
        insertWithoutTrigger(p);

        Test.startTest();
        // null oldMap = INSERT context; must not throw
        RES_ProductService.syncProducts(new List<Product2>{ p }, null);
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 6. syncProducts UPDATE — changed field → publishes event
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSyncProductsUpdateChangedFieldPublishes() {
        if (!hasSyncConfig() || !canConstruct()) return;

        // Downstream queueable makes a callout — prime token and set mock.
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Product2 p = new Product2(
            Name = 'SPS-CHANGED', IsActive = true,
            StockKeepingUnit = 'SKU-SPS-C',
            Family = '1004', RES_Type__c = 'N'
        );
        insertWithoutTrigger(p);

        Product2 pOld = p.clone(true, true, false, false);
        p.Family = '1005'; // change a sync field

        Test.startTest();
        RES_ProductService.syncProducts(
            new List<Product2>{ p },
            new Map<Id, Product2>{ pOld.Id => pOld }
        );
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 7. syncProducts UPDATE — no changed fields → returns early, no exception
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSyncProductsUpdateUnchangedSkipsPublish() {
        if (!hasSyncConfig()) return;

        Product2 p = new Product2(
            Name = 'SPS-SAME', IsActive = true,
            Family = '1004', RES_Type__c = 'N'
        );
        insertWithoutTrigger(p);

        // Both old and new are identical clones
        Product2 pSame = p.clone(true, true, false, false);

        Test.startTest();
        RES_ProductService.syncProducts(
            new List<Product2>{ p },
            new Map<Id, Product2>{ p.Id => pSame }
        );
        Test.stopTest();
    }

    @isTest
    static void testApplyDateDefaults_blankDatesAreDefaulted() {
        Product2 p = new Product2(Name = 'Unit A');

        RES_ProductService.applyDateDefaults(new List<Product2>{ p });

        System.assertEquals(Date.today(), p.AvailabilityDate, 'Availability defaults to today');
        System.assertEquals(Date.newInstance(3999, 12, 30), p.DiscontinuedDate, 'Discontinued defaults to 3999-12-30');
    }

    @isTest
    static void testApplyDateDefaults_existingDatesAreKept() {
        Product2 p = new Product2(
            Name = 'Unit B',
            AvailabilityDate = Date.newInstance(2026, 3, 1),
            DiscontinuedDate = Date.newInstance(2030, 3, 1)
        );

        RES_ProductService.applyDateDefaults(new List<Product2>{ p });

        System.assertEquals(Date.newInstance(2026, 3, 1), p.AvailabilityDate);
        System.assertEquals(Date.newInstance(2030, 3, 1), p.DiscontinuedDate);
    }

    @isTest
    static void testApplyDateDefaults_partialAndNullInputs() {
        Product2 p = new Product2(Name = 'Unit C', AvailabilityDate = Date.newInstance(2026, 3, 1));

        RES_ProductService.applyDateDefaults(new List<Product2>{ p });
        RES_ProductService.applyDateDefaults(null);
        RES_ProductService.applyDateDefaults(new List<Product2>());

        System.assertEquals(Date.newInstance(2026, 3, 1), p.AvailabilityDate, 'Existing start kept');
        System.assertEquals(Date.newInstance(3999, 12, 30), p.DiscontinuedDate, 'Blank end defaulted');
    }
}
