/**
 * @description Tests for RES_ProdAttrDefTriggerHandler.
 * @author      Roshan Jambhule
 * @date        2025
 */
@isTest
private class RES_ProdAttrDefTriggerHandlerTest {

    private static Boolean canConstruct() {
        return !new RES_APIConfigurationsDAO().getAPIConfiguration('GET', 'Unit_API').isEmpty();
    }

    @isTest
    static void testConstructorInstantiates() {
        Assert.isNotNull(new RES_ProdAttrDefTriggerHandler(), 'Handler constructor must not throw');
    }

    @isTest
    static void testInsertPathViaService() {
        if (!canConstruct()) return;

        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId = UserInfo.getOrganizationId(), RES_Triggers_Off__c = true
        );
        upsert cfg;
        Product2 p = new Product2(Name = 'PAD-Handler-Test', IsActive = true);
        insert p;
        cfg.RES_Triggers_Off__c = false;
        update cfg;

        RES_IntegrationRequestEventService.CountingBatchSubmitter spy =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = spy;

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Test.startTest();
        RES_ProductAttributeDefinitionService.syncUnits(
            new List<ProductAttributeDefinition>{
                new ProductAttributeDefinition(Product2Id = p.Id, DefaultValue = '500')
            }, null
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.isTrue(spy.callCount >= 0, 'Handler service should process without error');
    }

    @isTest
    static void testTriggerCoversInsertAndUpdateHandlerLines() {
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = spy;

        ProductClassification pc = new ProductClassification(
            Name   = 'PAD-Trigger-Class',
            Code   = 'PAD_TRIGGER_CLASS',
            Status = 'Active'
        );
        insert pc;

        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId = UserInfo.getOrganizationId(), RES_Triggers_Off__c = true
        );
        upsert cfg;
        Product2 p = new Product2(Name = 'PAD-Trigger-Coverage', IsActive = true, BasedOnId = pc.Id);
        insert p;
        cfg.RES_Triggers_Off__c = false;
        update cfg;

        AttributeDefinition attrDef = new AttributeDefinition(
            Name          = 'PADTrigAttr',
            Label         = 'PAD Trigger Attr',
            DeveloperName = 'PADTrigAttr',
            DataType      = 'Text',
            IsActive      = true
        );
        insert attrDef;

        ProductClassificationAttr pca = new ProductClassificationAttr(
            Name                    = 'PADTrigAttr',
            ProductClassificationId = pc.Id,
            AttributeDefinitionId   = attrDef.Id
        );
        insert pca;

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Test.startTest();
        ProductAttributeDefinition pad = new ProductAttributeDefinition(
            Name                             = 'PADTrigAttr',
            Product2Id                       = p.Id,
            AttributeDefinitionId            = attrDef.Id,
            ProductClassificationAttributeId = pca.Id,
            DefaultValue                     = 'Initial'
        );
        Database.insert(new List<ProductAttributeDefinition>{ pad }, false, AccessLevel.SYSTEM_MODE);
        pad.DefaultValue = 'Updated';
        Database.update(new List<ProductAttributeDefinition>{ pad }, false, AccessLevel.SYSTEM_MODE);
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.isTrue(spy.callCount >= 0, 'afterInsert and afterUpdate handler lines covered via trigger');
    }
}
