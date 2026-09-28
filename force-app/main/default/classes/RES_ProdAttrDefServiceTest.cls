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
}
