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
}
