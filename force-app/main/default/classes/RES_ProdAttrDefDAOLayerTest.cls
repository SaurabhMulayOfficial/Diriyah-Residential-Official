/**
 * @description Tests for RES_ProductAttributeDefinitionDAOLayer — covers all three query methods
 *              with null/empty inputs (early return) and valid Id inputs (query execution).
 * @author      Roshan Jambhule
 */
@isTest
private class RES_ProdAttrDefDAOLayerTest {

    private static RES_ProductAttributeDefinitionDAOLayer dao = new RES_ProductAttributeDefinitionDAOLayer();

    // ── getAttributeDefinitionsByProductsAndAttrs ────────────────────────────

    @isTest
    static void getByProductsAndAttrs_nullProductIds_returnsEmpty() {
        List<ProductAttributeDefinition> result =
            dao.getAttributeDefinitionsByProductsAndAttrs(null, new Set<Id>{ UserInfo.getUserId() });
        Assert.areEqual(0, result.size(), 'Null productIds must return empty list');
    }

    @isTest
    static void getByProductsAndAttrs_emptyProductIds_returnsEmpty() {
        List<ProductAttributeDefinition> result =
            dao.getAttributeDefinitionsByProductsAndAttrs(new Set<Id>(), new Set<Id>{ UserInfo.getUserId() });
        Assert.areEqual(0, result.size(), 'Empty productIds must return empty list');
    }

    @isTest
    static void getByProductsAndAttrs_nullAttrIds_returnsEmpty() {
        List<ProductAttributeDefinition> result =
            dao.getAttributeDefinitionsByProductsAndAttrs(new Set<Id>{ UserInfo.getUserId() }, null);
        Assert.areEqual(0, result.size(), 'Null attrIds must return empty list');
    }

    @isTest
    static void getByProductsAndAttrs_emptyAttrIds_returnsEmpty() {
        List<ProductAttributeDefinition> result =
            dao.getAttributeDefinitionsByProductsAndAttrs(new Set<Id>{ UserInfo.getUserId() }, new Set<Id>());
        Assert.areEqual(0, result.size(), 'Empty attrIds must return empty list');
    }

    @isTest
    static void getByProductsAndAttrs_validIds_executesQuery() {
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId = UserInfo.getOrganizationId(), RES_Triggers_Off__c = true
        );
        upsert cfg;
        Product2 p = new Product2(Name = 'DAO-PAD-Test', IsActive = true);
        insert p;

        AttributeDefinition attrDef = new AttributeDefinition(
            Name = 'DAOTestAttr', Label = 'DAO Test Attr',
            DeveloperName = 'DAOTestAttr', DataType = 'Text', IsActive = true
        );
        insert attrDef;

        Test.startTest();
        List<ProductAttributeDefinition> result =
            dao.getAttributeDefinitionsByProductsAndAttrs(
                new Set<Id>{ p.Id }, new Set<Id>{ attrDef.Id }
            );
        Test.stopTest();

        Assert.isNotNull(result, 'Result must not be null');
    }

    // ── getProductAttributeDefinitionsByAttrId ───────────────────────────────

    @isTest
    static void getByAttrId_nullProductIds_returnsEmpty() {
        List<ProductAttributeDefinition> result =
            dao.getProductAttributeDefinitionsByAttrId(null, UserInfo.getUserId());
        Assert.areEqual(0, result.size(), 'Null productIds must return empty list');
    }

    @isTest
    static void getByAttrId_emptyProductIds_returnsEmpty() {
        List<ProductAttributeDefinition> result =
            dao.getProductAttributeDefinitionsByAttrId(new Set<Id>(), UserInfo.getUserId());
        Assert.areEqual(0, result.size(), 'Empty productIds must return empty list');
    }

    @isTest
    static void getByAttrId_nullSelectorAttrId_returnsEmpty() {
        List<ProductAttributeDefinition> result =
            dao.getProductAttributeDefinitionsByAttrId(new Set<Id>{ UserInfo.getUserId() }, null);
        Assert.areEqual(0, result.size(), 'Null selectorAttrId must return empty list');
    }

    @isTest
    static void getByAttrId_validIds_executesQuery() {
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId = UserInfo.getOrganizationId(), RES_Triggers_Off__c = true
        );
        upsert cfg;
        Product2 p = new Product2(Name = 'DAO-PAD-ByAttrId', IsActive = true);
        insert p;

        AttributeDefinition attrDef = new AttributeDefinition(
            Name = 'DAOAttrIdTest', Label = 'DAO AttrId Test',
            DeveloperName = 'DAOAttrIdTest', DataType = 'Text', IsActive = true
        );
        insert attrDef;

        Test.startTest();
        List<ProductAttributeDefinition> result =
            dao.getProductAttributeDefinitionsByAttrId(new Set<Id>{ p.Id }, attrDef.Id);
        Test.stopTest();

        Assert.isNotNull(result, 'Result must not be null');
    }

    // ── getByProductIds ──────────────────────────────────────────────────────

    @isTest
    static void getByProductIds_nullIds_returnsEmpty() {
        List<ProductAttributeDefinition> result = dao.getByProductIds(null);
        Assert.areEqual(0, result.size(), 'Null productIds must return empty list');
    }

    @isTest
    static void getByProductIds_emptyIds_returnsEmpty() {
        List<ProductAttributeDefinition> result = dao.getByProductIds(new Set<Id>());
        Assert.areEqual(0, result.size(), 'Empty productIds must return empty list');
    }

    @isTest
    static void getByProductIds_validIds_executesQuery() {
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId = UserInfo.getOrganizationId(), RES_Triggers_Off__c = true
        );
        upsert cfg;
        Product2 p = new Product2(Name = 'DAO-PAD-ByProdId', IsActive = true);
        insert p;

        Test.startTest();
        List<ProductAttributeDefinition> result = dao.getByProductIds(new Set<Id>{ p.Id });
        Test.stopTest();

        Assert.isNotNull(result, 'Result must not be null');
    }
}
