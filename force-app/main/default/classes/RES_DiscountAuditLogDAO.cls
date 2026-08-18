/**
 * Class Name   : RES_DiscountAuditLogDAO
 * Description  : Data Access Object (DAO) layer for the RES_Discount_Audit_Log__c object.
 *                Provides standardized methods for querying Discount Audit Log records.
 *
 * Framework Rule:
 *      - All DAO layers must extend RES_BaseDAOLayer.
 *      - Each implementation must override getSObjectName()
 *        to specify the associated SObject.
 */
public with sharing class RES_DiscountAuditLogDAO extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'RES_Discount_Audit_Log__c';
    }

    public RES_Discount_Audit_Log__c getById(Id recordId) {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('recordId', recordId);

        String soql = 'SELECT Id, Name, RES_Entry_Type__c, RES_Quote__c ' +
                      'FROM RES_Discount_Audit_Log__c ' +
                      'WHERE Id = :recordId ' +
                      'LIMIT 1';

        List<SObject> results = executeQuery(soql, 'byId_' + recordId, false, bindVars, AccessLevel.SYSTEM_MODE);

        return results.isEmpty() ? null : (RES_Discount_Audit_Log__c) results[0];
    }
}
