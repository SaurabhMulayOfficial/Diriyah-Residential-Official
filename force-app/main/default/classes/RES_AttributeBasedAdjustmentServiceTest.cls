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
}
