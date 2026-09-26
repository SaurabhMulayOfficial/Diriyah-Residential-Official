/**
 * Class Name   : RES_InstallmentDAOLayer
 * Description  : Data Access Object (DAO) layer for the RES_Installment__c object.
 *
 * @author Saurabh Mulay
 */
public with sharing class RES_InstallmentDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'RES_Installment__c';
    }

    public List<RES_Installment__c> getInstallmentsByIds(Set<Id> installmentIds) {
        if (installmentIds == null || installmentIds.isEmpty()) {
            return new List<RES_Installment__c>();
        }

        Map<String, Object> bindVars = new Map<String, Object>{
            'installmentIds' => installmentIds
        };

        String soql =
            'SELECT Id ' +
            'FROM RES_Installment__c ' +
            'WHERE Id IN :installmentIds';

        return (List<RES_Installment__c>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}
