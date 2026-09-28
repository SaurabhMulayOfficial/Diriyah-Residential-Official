/**
 * @description Tests for RES_ProductAttributeDefinitionService — change-detection and event-publishing logic.
 * @author      Roshan Jambhule
 * @date        2025
 */
@isTest
private class RES_ProdAttrDefServiceTest {

    @isTest
    static void testIsDefinitionChangedFalseWhenIdentical() {
        ProductAttributeDefinition pad = new ProductAttributeDefinition(
            DefaultValue = '50000',
            Status       = 'Active'
        );

        Assert.isFalse(
            RES_ProductAttributeDefinitionService.isDefinitionChanged(pad, pad),
            'Identical records must not be considered changed'
        );
    }

    @isTest
    static void testIsDefinitionChangedTrueOnDefaultValueChange() {
        ProductAttributeDefinition newPad = new ProductAttributeDefinition(DefaultValue = '60000');
        ProductAttributeDefinition oldPad = new ProductAttributeDefinition(DefaultValue = '50000');

        Assert.isTrue(
            RES_ProductAttributeDefinitionService.isDefinitionChanged(newPad, oldPad),
            'Changed DefaultValue must be detected'
        );
    }

    @isTest
    static void testIsDefinitionChangedTrueOnValidFromChange() {
        ProductAttributeDefinition newPad = new ProductAttributeDefinition(
            DefaultValue      = '50000',
            RES_Valid_From__c = Date.newInstance(2026, 2, 1)
        );
        ProductAttributeDefinition oldPad = new ProductAttributeDefinition(
            DefaultValue      = '50000',
            RES_Valid_From__c = Date.newInstance(2026, 1, 1)
        );

        Assert.isTrue(
            RES_ProductAttributeDefinitionService.isDefinitionChanged(newPad, oldPad),
            'Changed RES_Valid_From__c must be detected'
        );
    }

    @isTest
    static void testIsDefinitionChangedTrueOnStatusChange() {
        ProductAttributeDefinition newPad = new ProductAttributeDefinition(Status = 'Inactive');
        ProductAttributeDefinition oldPad = new ProductAttributeDefinition(Status = 'Active');

        Assert.isTrue(
            RES_ProductAttributeDefinitionService.isDefinitionChanged(newPad, oldPad),
            'Changed Status must be detected'
        );
    }

    @isTest
    static void testSyncUnitsSkipsNullProduct2Id() {
        ProductAttributeDefinition pad = new ProductAttributeDefinition();

        Test.startTest();
        RES_ProductAttributeDefinitionService.syncUnits(
            new List<ProductAttributeDefinition>{ pad }, null
        );
        Test.stopTest();
    }

    @isTest
    static void testSyncUnitsEmptyListNoException() {
        Test.startTest();
        RES_ProductAttributeDefinitionService.syncUnits(
            new List<ProductAttributeDefinition>(), null
        );
        Test.stopTest();
    }

    @isTest
    static void testSyncUnitsInsertPublishesEventForProduct2Id() {
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId = UserInfo.getOrganizationId(), RES_Triggers_Off__c = true
        );
        upsert cfg;
        Product2 p = new Product2(Name = 'PAD-Coverage', IsActive = true);
        insert p;
        cfg.RES_Triggers_Off__c = false;
        update cfg;

        RES_IntegrationRequestEventService.CountingBatchSubmitter spy =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = spy;

        ProductAttributeDefinition pad = new ProductAttributeDefinition(Product2Id = p.Id, DefaultValue = '100');

        Test.startTest();
        RES_ProductAttributeDefinitionService.syncUnits(
            new List<ProductAttributeDefinition>{ pad }, null
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.isTrue(spy.callCount > 0, 'INSERT with a valid Product2Id must publish a Unit_Sync batch job');
    }

    @isTest
    static void testSyncUnitsUpdatePublishesEventWhenNotInOldMap() {
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId = UserInfo.getOrganizationId(), RES_Triggers_Off__c = true
        );
        upsert cfg;
        Product2 p = new Product2(Name = 'PAD-Coverage-Update', IsActive = true);
        insert p;
        cfg.RES_Triggers_Off__c = false;
        update cfg;

        RES_IntegrationRequestEventService.CountingBatchSubmitter spy =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = spy;

        ProductAttributeDefinition pad = new ProductAttributeDefinition(Product2Id = p.Id, DefaultValue = '200');

        Test.startTest();
        RES_ProductAttributeDefinitionService.syncUnits(
            new List<ProductAttributeDefinition>{ pad },
            new Map<Id, ProductAttributeDefinition>()
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.isTrue(spy.callCount > 0, 'UPDATE with record absent from oldMap must publish a Unit_Sync event');
    }

    @isTest
    static void testConstructorInstantiates() {
        Assert.isNotNull(new RES_ProductAttributeDefinitionService(), 'Constructor should succeed');
    }
}
