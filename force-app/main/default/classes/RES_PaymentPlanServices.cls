/**
 * @description Service layer for Payment Plan-related business operations.
 *              Provides reusable methods for processing and synchronizing
 *              Payment Plan records.
 *
 * @author Saurabh Mulay
 */
public with sharing class RES_PaymentPlanServices {
    public RES_PaymentPlanServices() {}

    public static void syncPaymentPlans(List<Product2> paymentPlans, Map<Id, Product2> oldMap) {
        List<Product2> paymentPlansToSync = new List<Product2>();

        RES_SAP_Integration_Config__mdt paymentPlanMDT =
            new RES_SAPIntegrationConfigDAO()
                .getSAPIntegrationConfigByDeveloperName('Payment_Plan');

        if (paymentPlanMDT == null || String.isBlank(paymentPlanMDT.RES_Sync_Fields__c)) {
            throw new RES_IntegrationException(
                'SAP Integration Config is Not available for "Payment_Plan", create and provide at least 1 field for change.'
            );
        }

        List<String> syncFieldLst = paymentPlanMDT.RES_Sync_Fields__c.split(',');
        Set<String> syncFields = new Set<String>();

        for (String field : syncFieldLst) {
            if (String.isNotBlank(field)) {
                syncFields.add(field.trim());
            }
        }

        String triggerContext = '';

        for (Product2 paymentPlan : paymentPlans) {
            if (oldMap == null) {
                paymentPlansToSync.add(paymentPlan);
            } 
            else if(isPaymentPlanApproved(paymentPlan, oldMap.get(paymentPlan.Id))){
                paymentPlansToSync.add(paymentPlan);
                triggerContext = 'I';
            }
            else if (isPaymentPlanChanged(paymentPlan, oldMap.get(paymentPlan.Id), syncFields) && paymentPlan.RES_Last_Sync_DateTime__c != null) {
                paymentPlansToSync.add(paymentPlan);
                triggerContext = 'U';
            }
        }
        if (paymentPlansToSync.isEmpty()) {
            return;
        }

        List<RES_Integration_Request__e> integrationRequestEventList = new List<RES_Integration_Request__e>();

        for (Product2 pp : paymentPlansToSync) {
            RES_Integration_Request__e req = new RES_Integration_Request__e();
            req.RES_RecordIds__c = String.valueOf(pp.Id);
            req.RES_Request_Method__c = 'GET';
            req.RES_Triggering_Context__c = triggerContext;
            req.RES_Service_Name__c = 'Payment_Plan';
            integrationRequestEventList.add(req);
        }
        try {
            if (!integrationRequestEventList.isEmpty()) {
                EventBus.publish(integrationRequestEventList);
            }
        } catch (Exception e) {
            System.debug('Exception Firing Integration Request Event ' + e.getMessage());
        }
    }

    private static Boolean isPaymentPlanChanged(Product2 newRecord, Product2 oldRecord, Set<String> syncFields) {
        if (oldRecord == null) {
            return true;
        }

        for (String fieldName : syncFields) {
            Object newValue = newRecord.get(fieldName);
            Object oldValue = oldRecord.get(fieldName);

            if (String.valueOf(newValue) != String.valueOf(oldValue)) {
                return true;
            }
        }
        return false;
    }
    
    private static Boolean isPaymentPlanApproved(Product2 newRecord, Product2 oldRecord) {
        if ((newRecord.RES_Approval_Status__c == 'Approved' && newRecord.RES_Approval_Status__c != oldRecord.RES_Approval_Status__c) && 
            (newRecord.IsActive  == true && newRecord.IsActive  != oldRecord.IsActive)) {
                return true;
            }
        return false;
    }
}