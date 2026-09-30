/**
 * @description Tests for RES_AttributeBasedAdjustmentService — change-detection and event-publishing logic.
 * @author      Roshan Jambhule
 * @date        2025
 */
@isTest
private class RES_AttributeBasedAdjustmentServiceTest {

    @isTest
    static void testIsAdjustmentChangedFalseWhenIdentical() {
        AttributeBasedAdjustment aba = new AttributeBasedAdjustment(
            AdjustmentValue = 5000,
            AdjustmentType  = 'Discount'
        );

        Assert.isFalse(
            RES_AttributeBasedAdjustmentService.isAdjustmentChanged(aba, aba),
            'Identical records must not be considered changed'
        );
    }

    @isTest
    static void testIsAdjustmentChangedTrueOnValueChange() {
        AttributeBasedAdjustment newAba = new AttributeBasedAdjustment(AdjustmentValue = 6000);
        AttributeBasedAdjustment oldAba = new AttributeBasedAdjustment(AdjustmentValue = 5000);

        Assert.isTrue(
            RES_AttributeBasedAdjustmentService.isAdjustmentChanged(newAba, oldAba),
            'Different AdjustmentValue must be detected as changed'
        );
    }

    @isTest
    static void testIsAdjustmentChangedTrueOnEffectiveFromChange() {
        AttributeBasedAdjustment newAba = new AttributeBasedAdjustment(
            AdjustmentValue = 5000,
            EffectiveFrom   = Datetime.newInstance(2026, 2, 1, 0, 0, 0)
        );
        AttributeBasedAdjustment oldAba = new AttributeBasedAdjustment(
            AdjustmentValue = 5000,
            EffectiveFrom   = Datetime.newInstance(2026, 1, 1, 0, 0, 0)
        );

        Assert.isTrue(
            RES_AttributeBasedAdjustmentService.isAdjustmentChanged(newAba, oldAba),
            'Changed EffectiveFrom must be detected'
        );
    }

    @isTest
    static void testIsAdjustmentChangedTrueOnTypeChange() {
        AttributeBasedAdjustment newAba = new AttributeBasedAdjustment(AdjustmentType = 'Surcharge');
        AttributeBasedAdjustment oldAba = new AttributeBasedAdjustment(AdjustmentType = 'Discount');

        Assert.isTrue(
            RES_AttributeBasedAdjustmentService.isAdjustmentChanged(newAba, oldAba),
            'Changed AdjustmentType must be detected'
        );
    }

    @isTest
    static void testSyncUnitsSkipsNullProductId() {
        AttributeBasedAdjustment aba = new AttributeBasedAdjustment();

        Test.startTest();
        RES_AttributeBasedAdjustmentService.syncUnits(
            new List<AttributeBasedAdjustment>{ aba }, null
        );
        Test.stopTest();
    }

    @isTest
    static void testSyncUnitsUpdateNoChangeSkips() {
        AttributeBasedAdjustment aba    = new AttributeBasedAdjustment(AdjustmentValue = 5000);
        AttributeBasedAdjustment oldAba = new AttributeBasedAdjustment(AdjustmentValue = 5000);

        Test.startTest();
        RES_AttributeBasedAdjustmentService.syncUnits(
            new List<AttributeBasedAdjustment>{ aba },
            new Map<Id, AttributeBasedAdjustment>()
        );
        Test.stopTest();
    }

    @isTest
    static void testSyncUnitsEmptyListNoException() {
        Test.startTest();
        RES_AttributeBasedAdjustmentService.syncUnits(
            new List<AttributeBasedAdjustment>(), null
        );
        Test.stopTest();
    }

    @isTest
    static void testSyncUnitsInsertPublishesEventForProductId() {
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId = UserInfo.getOrganizationId(), RES_Triggers_Off__c = true
        );
        upsert cfg;
        Product2 p = new Product2(Name = 'ABA-Coverage', IsActive = true);
        insert p;
        cfg.RES_Triggers_Off__c = false;
        update cfg;

        RES_IntegrationRequestEventService.CountingBatchSubmitter spy =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = spy;

        AttributeBasedAdjustment aba = new AttributeBasedAdjustment(ProductId = p.Id, AdjustmentValue = 5000);

        Test.startTest();
        RES_AttributeBasedAdjustmentService.syncUnits(
            new List<AttributeBasedAdjustment>{ aba }, null
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.isTrue(spy.callCount > 0, 'INSERT with a valid ProductId must publish a Unit_Sync batch job');
    }

    @isTest
    static void testSyncUnitsUpdatePublishesEventWhenNotInOldMap() {
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId = UserInfo.getOrganizationId(), RES_Triggers_Off__c = true
        );
        upsert cfg;
        Product2 p = new Product2(Name = 'ABA-Coverage-Update', IsActive = true);
        insert p;
        cfg.RES_Triggers_Off__c = false;
        update cfg;

        RES_IntegrationRequestEventService.CountingBatchSubmitter spy =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = spy;

        AttributeBasedAdjustment aba = new AttributeBasedAdjustment(
            ProductId = p.Id, AdjustmentValue = 6000, AdjustmentType = 'Discount'
        );

        Test.startTest();
        // empty oldMap → aba.Id not found → treated as changed → event published
        RES_AttributeBasedAdjustmentService.syncUnits(
            new List<AttributeBasedAdjustment>{ aba },
            new Map<Id, AttributeBasedAdjustment>()
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.isTrue(spy.callCount > 0, 'UPDATE with record absent from oldMap must publish a Unit_Sync event');
    }

    @isTest
    static void testConstructorInstantiates() {
        Assert.isNotNull(new RES_AttributeBasedAdjustmentService(), 'Constructor should succeed');
    }
}
