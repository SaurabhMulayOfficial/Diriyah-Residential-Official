/*
 * Class Name  : RES_ProductSellingModelOptionDAOLayer
 * Description : DAO layer for ProductSellingModelOption object.
 */
public without sharing class RES_ProductSellingModelOptionDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ProductSellingModelOption';
    }

    public List<ProductSellingModelOption> getSellingModelOptionsByProductIds(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) return new List<ProductSellingModelOption>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'productIds' => productIds };
        String soql = 'SELECT Product2Id, ProductSellingModelId FROM ProductSellingModelOption WHERE Product2Id IN :productIds';
        return (List<ProductSellingModelOption>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}