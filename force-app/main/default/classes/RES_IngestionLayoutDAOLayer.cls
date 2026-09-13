/*
 * Class Name  : RES_IngestionLayoutDAOLayer
 * Description : DAO layer for RES_Ingestion_Layout__mdt metadata object.
 */
public without sharing class RES_IngestionLayoutDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'RES_Ingestion_Layout__mdt';
    }

    public List<RES_Ingestion_Layout__mdt> getActiveLayouts() {
        String soql = 'SELECT Label, RES_Layout_Code__c, RES_Key_Column__c, RES_Product_Record_Type__c, ' +
                      'RES_Expected_Inventory_Type__c, RES_Inventory_Type_Column__c, ' +
                      'RES_Pricebook_Name__c, RES_Product_Classification__c, ' +
                      'RES_Selector_Attribute__c, RES_Price_Adjustment_Schedule__c, ' +
                      'RES_Attribute_Category__c, RES_Display_Order__c, RES_Description__c ' +
                      'FROM RES_Ingestion_Layout__mdt ' +
                      'WHERE RES_Is_Active__c = true ' +
                      'ORDER BY RES_Display_Order__c NULLS LAST, Label';
        return (List<RES_Ingestion_Layout__mdt>) executeQuery(soql, 'getActiveLayouts', true, null, AccessLevel.SYSTEM_MODE);
    }
}