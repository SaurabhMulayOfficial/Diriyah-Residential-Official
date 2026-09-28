/**
 * @description Tests for RES_ProductService — change-detection and event-publishing logic.
 * @author      Roshan Jambhule
 * @date        2025
 */
@isTest
private class RES_ProductServiceTest {

    private static final String UNIT_SYNC = 'Unit_Sync';

    private static Boolean canConstruct() {
        return !new RES_APIConfigurationsDAO().getAPIConfiguration('GET', 'Unit_API').isEmpty();
    }

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

    private static Boolean hasSyncConfig() {
        RES_SAP_Integration_Config__mdt config =
            new RES_SAPIntegrationConfigDAO().getSAPIntegrationConfigByDeveloperName(UNIT_SYNC);
        return config != null && String.isNotBlank(config.RES_Sync_Fields__c);
    }

    @isTest
    static void testIsProductChangedReturnsFalseWhenUnchanged() {
        Product2 p1 = new Product2(Family = '1004', RES_Unit_Status__c = 'Available');
        Product2 p2 = new Product2(Family = '1004', RES_Unit_Status__c = 'Available');

        Boolean changed = RES_ProductService.isProductChanged(
            p1, p2, new Set<String>{ 'Family', 'RES_Unit_Status__c' }
        );

        Assert.isFalse(changed, 'No changed fields must return false');
    }

    @isTest
    static void testIsProductChangedReturnsTrueWhenFieldDiffers() {
        Product2 p1 = new Product2(Family = '1004');
        Product2 p2 = new Product2(Family = '1005');

        Boolean changed = RES_ProductService.isProductChanged(
            p1, p2, new Set<String>{ 'Family' }
        );

        Assert.isTrue(changed, 'A changed field value must return true');
    }

    @isTest
    static void testIsProductChangedTrueWhenOldRecordNull() {
        Boolean changed = RES_ProductService.isProductChanged(
            new Product2(Family = '1004'), null, new Set<String>{ 'Family' }
        );

        Assert.isTrue(changed, 'Null oldRecord must always return true (new record scenario)');
    }

    @isTest
    static void testIsProductChangedSkipsInvalidField() {
        Product2 p1 = new Product2();
        Product2 p2 = new Product2();

        Boolean changed = RES_ProductService.isProductChanged(
            p1, p2, new Set<String>{ 'NonExistent_Field_XYZ__c', 'Family' }
        );

        Assert.isFalse(changed,
            'Unrecognised fields must be silently skipped; result for identical products must be false');
    }

    @isTest
    static void testSyncProductsInsertQueuesEvent() {
        if (!hasSyncConfig() || !canConstruct()) return;

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Product2 p = new Product2(
            Name = 'SPS-INSERT', IsActive = true,
            StockKeepingUnit = 'SKU-SPS-I',
            Family = '1004', RES_Type__c = 'N'
        );
        insertWithoutTrigger(p);

        Test.startTest();
        RES_ProductService.syncProducts(new List<Product2>{ p }, null);
        Test.stopTest();
    }

    @isTest
    static void testSyncProductsUpdateChangedFieldPublishes() {
        if (!hasSyncConfig() || !canConstruct()) return;

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Product2 p = new Product2(
            Name = 'SPS-CHANGED', IsActive = true,
            StockKeepingUnit = 'SKU-SPS-C',
            Family = '1004', RES_Type__c = 'N'
        );
        insertWithoutTrigger(p);

        Product2 pOld = p.clone(true, true, false, false);
        p.Family = '1005';

        Test.startTest();
        RES_ProductService.syncProducts(
            new List<Product2>{ p },
            new Map<Id, Product2>{ pOld.Id => pOld }
        );
        Test.stopTest();
    }

    @isTest
    static void testSyncProductsUpdateUnchangedSkipsPublish() {
        if (!hasSyncConfig()) return;

        Product2 p = new Product2(
            Name = 'SPS-SAME', IsActive = true,
            Family = '1004', RES_Type__c = 'N'
        );
        insertWithoutTrigger(p);

        Product2 pSame = p.clone(true, true, false, false);

        Test.startTest();
        RES_ProductService.syncProducts(
            new List<Product2>{ p },
            new Map<Id, Product2>{ p.Id => pSame }
        );
        Test.stopTest();
    }
}
