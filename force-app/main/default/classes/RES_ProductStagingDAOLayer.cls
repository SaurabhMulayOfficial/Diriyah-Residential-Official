/**
 * Class Name  : RES_ProductStagingDAOLayer
 * Description : DAO layer for RES_Product_Staging__c object.
 */
public without sharing class RES_ProductStagingDAOLayer extends RES_BaseDAOLayer {

    protected override String getSObjectName() {
        return 'RES_Product_Staging__c';
    }

    public List<AggregateResult> getStatusCountsByBatchId(String batchId) {
        if (String.isBlank(batchId)) return new List<AggregateResult>();

        Map<String, Object> bindVars = new Map<String, Object>{'batchId' => batchId};

        String soql =
            'SELECT RES_Processing_Status__c st, COUNT(Id) c ' +
            'FROM RES_Product_Staging__c ' +
            'WHERE RES_Batch_Id__c = :batchId ' +
            'GROUP BY RES_Processing_Status__c';

        List<SObject> results = executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);

        return (List<AggregateResult>) results;
    }

    /** Distinct unit codes still pending for one import, so the batch can chunk by unit rather than by row. */
    public List<String> getPendingUnitCodes(String batchId) {
        List<String> codes = new List<String>();
        if (String.isBlank(batchId)) return codes;

        Map<String, Object> bindVars = new Map<String, Object>{'batchId' => batchId};

        String soql =
            'SELECT RES_Product_Code__c code ' +
            'FROM RES_Product_Staging__c ' +
            'WHERE RES_Processing_Status__c = \'Pending\' ' +
            'AND RES_Batch_Id__c = :batchId ' +
            'AND RES_Product_Code__c != null ' +
            'GROUP BY RES_Product_Code__c ' +
            'ORDER BY RES_Product_Code__c';

        for (SObject ar : executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE)) {
            codes.add((String) ar.get('code'));
        }
        return codes;
    }

    /** Every pending staging row (all conditions) for the given units within one import. */
    public List<RES_Product_Staging__c> getPendingStagingRecordsByCodes(String batchId, List<String> codes) {
        if (String.isBlank(batchId) || codes == null || codes.isEmpty()) return new List<RES_Product_Staging__c>();

        List<String> fields = new List<String>(
            RES_Product_Staging__c.SObjectType.getDescribe().fields.getMap().keySet()
        );

        Map<String, Object> bindVars = new Map<String, Object>{'batchId' => batchId, 'codes' => codes};

        String soql =
            'SELECT ' + String.join(fields, ', ') +
            ' FROM RES_Product_Staging__c' +
            ' WHERE RES_Processing_Status__c = \'Pending\'' +
            ' AND RES_Batch_Id__c = :batchId' +
            ' AND RES_Product_Code__c IN :codes' +
            ' ORDER BY RES_Product_Code__c, RES_Condition_Type__c';

        return (List<RES_Product_Staging__c>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}
