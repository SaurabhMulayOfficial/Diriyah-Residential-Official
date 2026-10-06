/*
 * Class Name  : RES_MeasurementDAOLayer
 * Description : DAO layer for RES_Measurement__c object.
 */
public without sharing class RES_MeasurementDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'RES_Measurement__c';
    }

    public List<RES_Measurement__c> getMeasurementsByProductIds(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) return new List<RES_Measurement__c>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'productIds' => productIds };
        String soql = 'SELECT Id, Name, CreatedDate, RES_Product__c, RES_Measurement_Type__c, RES_Measurement_Amount__c, ' +
                      'RES_Measurement_From__c, RES_Measurement_To__c, RES_Unit_Of_Measurement__c, RES_Last_Sync_DateTime__c ' +
                      'FROM RES_Measurement__c WHERE RES_Product__c IN :productIds';
        return (List<RES_Measurement__c>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public List<RES_Measurement__c> getMeasurementByIds(Set<Id> recordIds){
        Map<String, Object> bindVars = new Map<String, Object>{ 'recordIds' => recordIds };
        String soql = 'SELECT Id, RES_Measurement_From__c, RES_Catalog__c, RES_Measurement_To__c, RES_Measurement_Amount__c, RES_Category__c, RES_Measurement_Type__c, RES_Unit_Of_Measurement__c, RES_Product__c FROM RES_Measurement__c WHERE Id IN :recordIds';
        return (List<RES_Measurement__c>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    /** @description Measurements of the given types for the given products (active-window filtering is done by the caller). */
    public List<RES_Measurement__c> getMeasurementsByProductIdsAndTypes(Set<Id> productIds, Set<String> measurementTypes) {
        if (productIds == null || productIds.isEmpty() || measurementTypes == null || measurementTypes.isEmpty()) {
            return new List<RES_Measurement__c>();
        }
        Map<String, Object> bindVars = new Map<String, Object>{ 'productIds' => productIds, 'measurementTypes' => measurementTypes };
        String soql = 'SELECT Id, CreatedDate, RES_Product__c, RES_Measurement_Type__c, RES_Measurement_Amount__c, ' +
                      'RES_Measurement_From__c, RES_Measurement_To__c, RES_Unit_Of_Measurement__c ' +
                      'FROM RES_Measurement__c ' +
                      'WHERE RES_Product__c IN :productIds AND RES_Measurement_Type__c IN :measurementTypes';
        return (List<RES_Measurement__c>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}
