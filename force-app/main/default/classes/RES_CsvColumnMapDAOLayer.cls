/*
 * Class Name  : RES_CsvColumnMapDAOLayer
 * Description : DAO layer for RES_Csv_Column_Map__mdt metadata object.
 */
public without sharing class RES_CsvColumnMapDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'RES_Csv_Column_Map__mdt';
    }

    public List<RES_Csv_Column_Map__mdt> getActiveColumnMapsByLayoutCode(String layoutCode) {
        if (String.isBlank(layoutCode)) return new List<RES_Csv_Column_Map__mdt>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'layoutCode' => layoutCode };
        String soql = 'SELECT RES_Source_Header__c, RES_Header_Occurrence__c, RES_Staging_Field__c, ' +
                      'RES_Date_Format__c, RES_Strip_Thousand_Separators__c, RES_Is_Required__c, RES_Default_Value__c ' +
                      'FROM RES_Csv_Column_Map__mdt ' +
                      'WHERE RES_Is_Active__c = true AND RES_Layout__r.RES_Layout_Code__c = :layoutCode ' +
                      'ORDER BY RES_Sequence__c NULLS LAST';
        return (List<RES_Csv_Column_Map__mdt>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}