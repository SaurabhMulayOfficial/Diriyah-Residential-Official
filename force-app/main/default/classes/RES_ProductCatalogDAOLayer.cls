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
        String soql = 'SELECT Id, Code, RES_Geo_Location__c FROM ProductCatalog WHERE Code IN :codes';
        return (List<ProductCatalog>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public List<ProductCatalog> getCatalogByIds(Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<ProductCatalog>();
        }

        Map<String, Object> bindVars = new Map<String, Object>{
            'recordIds' => recordIds
        };

        String soql =
            'SELECT Id, Code, Name, CatalogType, ' +
            '       Description, RES_Bank_Address_AR__c, RES_Bank_Address_EN__c, RES_Bank_Name_AR__c, ' +
            '       RES_Bank_Name_EN__c, RES_Beneficiary_Name_AR__c, RES_Beneficiary_Name_EN__c, ' +
            '       RES_BP_Number__c, RES_BP_Role__c, RES_Geo_Location__c, RES_Business_Entity_Id__c, RES_City__c, ' +
            '       RES_City_Arabic__c, RES_Company_Code__c, RES_District__c, RES_District_Arabic__c, ' +
            '       EffectiveStartDate, EffectiveEndDate, RES_Geo_Latitude__c, RES_Geo_Longitude__c, ' +
            '       RES_Last_Sync_DateTime__c, RES_Master_Plan__c, RES_Measurement_Amount__c, ' +
            '       RES_Measurement_Type__c, RES_Measurement_Valid_From__c, RES_Measurement_Valid_To__c, ' +
            '       RES_Name_AR__c, RES_Profit_Center__c, RES_Geo_Location__Latitude__s, RES_Geo_Location__Longitude__s, RES_Swift__c, RES_Tenancy_Law__c ' +
            'FROM ProductCatalog ' +
            'WHERE Id IN :recordIds';

        return (List<ProductCatalog>) executeQuery(
            soql,
            '',
            false,
            bindVars,
            AccessLevel.SYSTEM_MODE
        );
    }
}