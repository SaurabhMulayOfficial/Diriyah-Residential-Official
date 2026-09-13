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
        String soql = 'SELECT Id, RES_Product__c, RES_Measurement_Type__c, RES_Measurement_Amount__c ' +
                      'FROM RES_Measurement__c WHERE RES_Product__c IN :productIds';
        return (List<RES_Measurement__c>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}