/*
 * Class Name  : RES_ProductDisqualificationDAOLayer
 * Description : DAO layer for ProductDisqualification object.
 */
public without sharing class RES_ProductDisqualificationDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ProductDisqualification';
    }

    public List<ProductDisqualification> getDisqualificationsByProductIds(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) return new List<ProductDisqualification>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'productIds' => productIds };
        String soql = 'SELECT ProductId FROM ProductDisqualification WHERE ProductId IN :productIds';
        return (List<ProductDisqualification>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}