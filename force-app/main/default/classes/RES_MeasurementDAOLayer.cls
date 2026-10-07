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

    /** @description All measurements (every type) of the given products, with the fields needed to decide which is Active. */
    public List<RES_Measurement__c> getMeasurementsForActiveSync(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) return new List<RES_Measurement__c>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'productIds' => productIds };
        String soql = 'SELECT Id, CreatedDate, RES_Product__c, RES_Measurement_Type__c, RES_Measurement_Amount__c, ' +
                      'RES_Measurement_From__c, RES_Measurement_To__c, RES_Unit_Of_Measurement__c, RES_Active__c ' +
                      'FROM RES_Measurement__c WHERE RES_Product__c IN :productIds';
        return (List<RES_Measurement__c>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    /** @description Every measurement that belongs to a product (one-off full backfill). Batch scope; callers read RES_Product__c. */
    public Database.QueryLocator getProductMeasurementsLocator() {
        String soql = 'SELECT Id, RES_Product__c FROM RES_Measurement__c WHERE RES_Product__c != null';
        return executeBatchQuery(soql, null, AccessLevel.SYSTEM_MODE);
    }

    /** @description Product measurements whose From or To date falls in [fromDate, toDate] (daily boundary batch scope). */
    public Database.QueryLocator getProductMeasurementsBoundaryLocator(Date fromDate, Date toDate) {
        Map<String, Object> bindVars = new Map<String, Object>{ 'fromDate' => fromDate, 'toDate' => toDate };
        String soql = 'SELECT Id, RES_Product__c FROM RES_Measurement__c WHERE RES_Product__c != null ' +
                      'AND ((RES_Measurement_From__c >= :fromDate AND RES_Measurement_From__c <= :toDate) ' +
                      'OR (RES_Measurement_To__c >= :fromDate AND RES_Measurement_To__c <= :toDate))';
        return executeBatchQuery(soql, bindVars, AccessLevel.SYSTEM_MODE);
    }
}
