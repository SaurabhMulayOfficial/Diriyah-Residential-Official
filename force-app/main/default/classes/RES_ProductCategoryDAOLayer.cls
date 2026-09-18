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

    public List<ProductCategory> getCategoriesByIds(Set<Id> categoryIds) {
        if (categoryIds == null || categoryIds.isEmpty()) return new List<ProductCategory>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'categoryIds' => categoryIds };
        String soql = 'SELECT Id, Name, RES_Company_Code__c, RES_Business_Entity_Id__c, RES_Property_ID__c, RES_Valid_From_Date__c, RES_Valid_To_Date__c, RES_Profit_Center__c, RES_Property_Type__c FROM ProductCategory WHERE Id IN :categoryIds';
        return (List<ProductCategory>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

}