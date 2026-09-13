/*
 * Class Name  : RES_ProductCatalogDAOLayer
 * Description : DAO layer for ProductCatalog object.
 */
public without sharing class RES_ProductCatalogDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ProductCatalog';
    }

    public List<ProductCatalog> getCatalogsByCodes(Set<String> codes) {
        if (codes == null || codes.isEmpty()) return new List<ProductCatalog>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'codes' => codes };
        String soql = 'SELECT Id, Code FROM ProductCatalog WHERE Code IN :codes';
        return (List<ProductCatalog>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}