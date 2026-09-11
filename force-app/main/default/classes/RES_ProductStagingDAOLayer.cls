/*
 * Class Name  : RES_ProductStagingDAOLayer
 * Description : DAO layer for RES_Product_Staging__c object.
 */
public without sharing class RES_ProductStagingDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'RES_Product_Staging__c';
    }

    public List<AggregateResult> getStatusCountsByBatchId(String batchId) {
        if (String.isBlank(batchId)) return new List<AggregateResult>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'batchId' => batchId };
        String soql = 'SELECT RES_Processing_Status__c st, COUNT(Id) c ' +
                      'FROM RES_Product_Staging__c WHERE RES_Batch_Id__c = :batchId ' +
                      'GROUP BY RES_Processing_Status__c';
        List<SObject> results = executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
        return (List<AggregateResult>) results;
    }

    public Database.QueryLocator getPendingStagingRecordsBatch() {
        List<String> fields = new List<String>(
            RES_Product_Staging__c.SObjectType.getDescribe().fields.getMap().keySet()
        );
        String soql = 'SELECT ' + String.join(fields, ', ') +
                      ' FROM RES_Product_Staging__c' +
                      ' WHERE RES_Processing_Status__c = \'Pending\'' +
                      ' ORDER BY RES_Product_Code__c, RES_Condition_Type__c';
        return executeBatchQuery(soql, null, AccessLevel.SYSTEM_MODE);
    }
}