/*
 * Class Name  : RES_ProductCategoryDAOLayer
 * Description : DAO layer for ProductCategory object.
 */
public without sharing class RES_ProductCategoryDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ProductCategory';
    }

    public List<ProductCategory> getCategoriesByCodes(Set<String> codes) {
        if (codes == null || codes.isEmpty()) return new List<ProductCategory>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'codes' => codes };
        String soql = 'SELECT Id, Code FROM ProductCategory WHERE Code IN :codes';
        return (List<ProductCategory>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}