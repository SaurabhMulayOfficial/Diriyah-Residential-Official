/*
 * Class Name  : RES_ProductCategoryProductDAOLayer
 * Description : DAO layer for ProductCategoryProduct object.
 */
public without sharing class RES_ProductCategoryProductDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ProductCategoryProduct';
    }

    public List<ProductCategoryProduct> getCategoryProductsByProductIds(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) return new List<ProductCategoryProduct>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'productIds' => productIds };
        String soql = 'SELECT ProductId, ProductCategoryId FROM ProductCategoryProduct WHERE ProductId IN :productIds';
        return (List<ProductCategoryProduct>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}