/*
 * Class Name  : RES_TargetFieldMapDAOLayer
 * Description : DAO layer for RES_Target_Field_Map__mdt metadata object.
 */
public without sharing class RES_TargetFieldMapDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'RES_Target_Field_Map__mdt';
    }

    public List<RES_Target_Field_Map__mdt> getActiveTargetMapsByLayoutCode(String layoutCode) {
        if (String.isBlank(layoutCode)) return new List<RES_Target_Field_Map__mdt>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'layoutCode' => layoutCode };
        String soql = 'SELECT RES_Staging_Field__c, RES_Target_Object__c, RES_Target_Field__c, ' +
                      'RES_Value_Kind__c, RES_Literal_Value__c, RES_Merge_Strategy__c, RES_Skip_On_Update__c, ' +
                      'RES_Measurement_Type__c, RES_Unit_Of_Measurement__c, RES_Attribute_Name__c, RES_Source_Code__c ' +
                      'FROM RES_Target_Field_Map__mdt ' +
                      'WHERE RES_Is_Active__c = true AND RES_Layout__r.RES_Layout_Code__c = :layoutCode ' +
                      'ORDER BY RES_Sequence__c NULLS LAST';
        return (List<RES_Target_Field_Map__mdt>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}