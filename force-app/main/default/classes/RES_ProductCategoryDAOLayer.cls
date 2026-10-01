/*
 * Class Name  : RES_ProductCategoryDAOLayer
 * Description : DAO layer for ProductCategory object.
 */
public without sharing class RES_ProductCategoryDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ProductCategory';
    }

    public List<ProductCategory> getCategoriesByBusinessEntityAndProperty(Set<String> businessEntityIds, Set<String> propertyIds) {
        if (businessEntityIds == null || businessEntityIds.isEmpty() || propertyIds == null || propertyIds.isEmpty()) {
            return new List<ProductCategory>();
        }
        Map<String, Object> bindVars = new Map<String, Object>{ 'beIds' => businessEntityIds, 'propIds' => propertyIds };
        // RES_Business_Entity_Id__c/RES_Property_Id__c are the real external identifiers synced from source; the standard Code field is not reliably populated. Caller matches the exact pair since this IN/IN query can over-fetch combinations.
        String soql = 'SELECT Id, RES_Business_Entity_Id__c, RES_Property_Id__c FROM ProductCategory ' +
                      'WHERE RES_Business_Entity_Id__c IN :beIds AND RES_Property_Id__c IN :propIds';
        return (List<ProductCategory>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public List<ProductCategory> getCategoriesByIds(Set<Id> categoryIds) {
        if (categoryIds == null || categoryIds.isEmpty()) return new List<ProductCategory>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'categoryIds' => categoryIds };
        String soql = 'SELECT Id, Name, RES_Company_Code__c, RES_Business_Entity_Id__c, RES_Property_ID__c, RES_Valid_From_Date__c, RES_Valid_To_Date__c, RES_Profit_Center__c, RES_Property_Type__c, RES_Last_Sync_DateTime__c FROM ProductCategory WHERE Id IN :categoryIds';
        return (List<ProductCategory>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

}