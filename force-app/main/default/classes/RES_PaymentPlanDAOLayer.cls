/**
 * Class Name   : RES_PaymentPlanDAOLayer
 * Description  : Data Access Object (DAO) layer for the RES_Payment_Plan__c object.
 *
 * @author Saurabh Mulay
 */
public with sharing class RES_PaymentPlanDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'RES_Payment_Plan__c';
    }

    public List<RES_Payment_Plan__c> getPaymentPlansByIds(Set<Id> paymentPlanIds) {
        if (paymentPlanIds == null || paymentPlanIds.isEmpty()) {
            return new List<RES_Payment_Plan__c>();
        }

        Map<String, Object> bindVars = new Map<String, Object>{
            'paymentPlanIds' => paymentPlanIds
        };

        String soql =
            'SELECT Id ' +
            'FROM RES_Payment_Plan__c ' +
            'WHERE Id IN :paymentPlanIds';

        return (List<RES_Payment_Plan__c>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}
