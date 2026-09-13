/*
 * Class Name  : RES_ProductAttributeDefinitionDAOLayer
 * Description : DAO layer for ProductAttributeDefinition object.
 */
public without sharing class RES_ProductAttributeDefinitionDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ProductAttributeDefinition';
    }

    public List<ProductAttributeDefinition> getAttributeDefinitionsByProductsAndAttrs(Set<Id> productIds, Set<Id> attrIds) {
        if (productIds == null || productIds.isEmpty() || attrIds == null || attrIds.isEmpty()) {
            return new List<ProductAttributeDefinition>();
        }
        Map<String, Object> bindVars = new Map<String, Object>{ 'productIds' => productIds, 'attrIds' => attrIds };
        String soql = 'SELECT Id, Product2Id, AttributeDefinitionId, DefaultValue ' +
                      'FROM ProductAttributeDefinition ' +
                      'WHERE Product2Id IN :productIds AND AttributeDefinitionId IN :attrIds';
        return (List<ProductAttributeDefinition>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public List<ProductAttributeDefinition> getProductAttributeDefinitionsByAttrId(Set<Id> productIds, Id selectorAttrId) {
        if (productIds == null || productIds.isEmpty() || selectorAttrId == null) {
            return new List<ProductAttributeDefinition>();
        }
        Map<String, Object> bindVars = new Map<String, Object>{ 'productIds' => productIds, 'selectorAttrId' => selectorAttrId };
        String soql = 'SELECT Product2Id FROM ProductAttributeDefinition ' +
                      'WHERE Product2Id IN :productIds AND AttributeDefinitionId = :selectorAttrId';
        return (List<ProductAttributeDefinition>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}