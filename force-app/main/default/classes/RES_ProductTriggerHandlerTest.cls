/**
 * @description Tests for RES_ProductTriggerHandler — Description defaulting and afterInsert integration.
 * @author      Roshan Jambhule
 * @date        2025
 */
@isTest
private class RES_ProductTriggerHandlerTest {

    private static Boolean canConstruct() {
        return !new RES_APIConfigurationsDAO().getAPIConfiguration('GET', 'Unit_API').isEmpty();
    }

    @isTest
    static void testBeforeInsertDefaultsDescriptionToName() {
        if (!canConstruct()) return;

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Product2 p = new Product2(
            Name             = 'TRIG-DESC-01',
            IsActive         = true,
            StockKeepingUnit = 'SKU-TRIG-01',
            ProductCode      = 'PC-TRIG-01',
            Family           = '1004',
            RES_Type__c      = 'N'
        );

        Test.startTest();
        insert p;
        Test.stopTest();

        Product2 after = [SELECT Description FROM Product2 WHERE Id = :p.Id];
        Assert.areEqual('TRIG-DESC-01', after.Description,
            'beforeInsert must set Description = Name when Description is blank and ProductCode is set');
    }

    @isTest
    static void testBeforeInsertPreservesExistingDescription() {
        if (!canConstruct()) return;

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Product2 p = new Product2(
            Name             = 'TRIG-DESC-02',
            IsActive         = true,
            StockKeepingUnit = 'SKU-TRIG-02',
            ProductCode      = 'PC-TRIG-02',
            Description      = 'Explicit Description',
            Family           = '1004',
            RES_Type__c      = 'N'
        );

        Test.startTest();
        insert p;
        Test.stopTest();

        Product2 after = [SELECT Description FROM Product2 WHERE Id = :p.Id];
        Assert.areEqual('Explicit Description', after.Description,
            'beforeInsert must not overwrite a non-blank Description');
    }

    @isTest
    static void testBeforeInsertNoDefaultWhenProductCodeBlank() {
        if (!canConstruct()) return;

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Product2 p = new Product2(
            Name             = 'TRIG-DESC-03',
            IsActive         = true,
            StockKeepingUnit = 'SKU-TRIG-03',
            Family           = '1004',
            RES_Type__c      = 'N'
        );

        Test.startTest();
        insert p;
        Test.stopTest();

        Product2 after = [SELECT Description FROM Product2 WHERE Id = :p.Id];
        Assert.isTrue(
            String.isBlank(after.Description),
            'beforeInsert must not set Description when ProductCode is also blank'
        );
    }

    @isTest
    static void testBeforeUpdateDefaultsDescriptionToName() {
        if (!canConstruct()) return;

        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId        = UserInfo.getOrganizationId(),
            RES_Triggers_Off__c = true
        );
        upsert cfg;
        Product2 p = new Product2(
            Name             = 'TRIG-DESC-04',
            IsActive         = true,
            StockKeepingUnit = 'SKU-TRIG-04',
            ProductCode      = 'PC-TRIG-04',
            Description      = 'Old Desc',
            Family           = '1004',
            RES_Type__c      = 'N'
        );
        insert p;
        cfg.RES_Triggers_Off__c = false;
        update cfg;

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        p.Description = null;

        Test.startTest();
        update p;
        Test.stopTest();

        Product2 after = [SELECT Description FROM Product2 WHERE Id = :p.Id];
        Assert.areEqual('TRIG-DESC-04', after.Description,
            'beforeUpdate must set Description = Name when Description is cleared and ProductCode is set');
    }

    @isTest
    static void testAfterInsertCallsIntegrationServiceWithoutException() {
        if (!canConstruct()) return;

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody =
            '{"Return":{"item":{"Type":"S","Message":"Unit created","MessageV4":"RO 1000/200/11099999"}}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Product2 p = new Product2(
            Name               = 'TRIG-AFTER-01',
            IsActive           = true,
            StockKeepingUnit   = 'SKU-AFT-01',
            ProductCode        = 'PC-AFT-01',
            Description        = 'After Insert Test',
            Family             = '1004',
            RES_Type__c        = 'N',
            RES_Floor__c       = '001',
            RES_Area_Type__c   = 'None',
            RES_Area__c        = 100.0,
            RES_Unit_Status__c = 'Available'
        );

        Test.startTest();
        insert p;
        Test.stopTest();
    }
}
