/**
 * @description Service layer for Payment Plan-related business operations.
 *              Provides reusable methods for processing and synchronizing
 *              Payment Plan records.
 *
 * @author Saurabh Mulay
 */
public with sharing class RES_PaymentPlanServices {
    private static final String DEACTIVATED_STAGE = 'Deactivated';

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

        Id paymentPlanRecordTypeId = Schema.SObjectType.Product2
            .getRecordTypeInfosByDeveloperName()
            .get('RES_Residential_Payment_Plan')
            .getRecordTypeId();
        
        for (Product2 paymentPlan : paymentPlans) {
            if(paymentPlan.RecordTypeId == paymentPlanRecordTypeId){
                if (oldMap == null && paymentPlan.IsActive == true && paymentPlan.RES_Approval_Status__c == 'Approved') {
                    paymentPlansToSync.add(paymentPlan);
                    triggerContext = 'I';
                } 
                else if(oldMap != null && isPaymentPlanApproved(paymentPlan, oldMap.get(paymentPlan.Id))){
                    paymentPlansToSync.add(paymentPlan);
                    triggerContext = 'I';
                }
                else if (oldMap != null && isPaymentPlanChanged(paymentPlan, oldMap.get(paymentPlan.Id), syncFields) && paymentPlan.RES_Last_Sync_DateTime__c != null) {
                    paymentPlansToSync.add(paymentPlan);
                    triggerContext = 'U';
                }
            }
        }
		system.debug('paymentPlansToSync ==> '+paymentPlansToSync);
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
		system.debug('integrationRequestEventList ==> '+integrationRequestEventList);
        try {
            if (!integrationRequestEventList.isEmpty()) {
                system.debug('EventBus.publish ==> '+integrationRequestEventList);
                EventBus.publish(integrationRequestEventList);
            }
        } catch (Exception e) {
            System.debug('Exception Firing Integration Request Event ' + e.getMessage());
        }
    }

    /**
     * @description After update: untags Payment Plans that reached the Deactivated stage from all Units they were provisioned on.
     *              Keyed on the stage, not IsActive alone: the approval orchestrations set IsActive = false on every pending stage.
     */
    public static void removeDeactivatedPlansFromUnits(List<Product2> paymentPlans, Map<Id, Product2> oldMap) {
        if (oldMap == null) {
            return;
        }
        Id paymentPlanRecordTypeId = Schema.SObjectType.Product2
            .getRecordTypeInfosByDeveloperName()
            .get('RES_Residential_Payment_Plan')
            .getRecordTypeId();

        Set<Id> deactivatedPlanIds = new Set<Id>();
        for (Product2 paymentPlan : paymentPlans) {
            Product2 oldRecord = oldMap.get(paymentPlan.Id);
            if (paymentPlan.RecordTypeId == paymentPlanRecordTypeId && paymentPlan.IsActive == false
                && paymentPlan.RES_Payment_Plan_Approval_Stage__c == DEACTIVATED_STAGE
                && oldRecord?.RES_Payment_Plan_Approval_Stage__c != DEACTIVATED_STAGE) {
                deactivatedPlanIds.add(paymentPlan.Id);
            }
        }
        if (!deactivatedPlanIds.isEmpty()) {
            RES_PaymentPlanExpiryService.removeDeactivatedPlans(deactivatedPlanIds);
        }
    }

    /** @description After update: re-tags an Approved Payment Plan to its catalog's Units when it turns active again. */
    public static void tagReactivatedPlansToUnits(List<Product2> paymentPlans, Map<Id, Product2> oldMap) {
        if (oldMap == null) {
            return;
        }
        Id paymentPlanRecordTypeId = Schema.SObjectType.Product2
            .getRecordTypeInfosByDeveloperName()
            .get('RES_Residential_Payment_Plan')
            .getRecordTypeId();

        Set<Id> reactivatedPlanIds = new Set<Id>();
        for (Product2 paymentPlan : paymentPlans) {
            Product2 oldRecord = oldMap.get(paymentPlan.Id);
            if (paymentPlan.RecordTypeId == paymentPlanRecordTypeId && paymentPlan.IsActive == true && oldRecord?.IsActive != true
                && paymentPlan.RES_Approval_Status__c == 'Approved') {
                reactivatedPlanIds.add(paymentPlan.Id);
            }
        }
        if (!reactivatedPlanIds.isEmpty()) {
            RES_PaymentPlanBundleProvisioner.provisionPlans(reactivatedPlanIds);
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
        system.debug('newRecord.RES_Approval_Status__c ==> '+newRecord.RES_Approval_Status__c);
        system.debug('oldRecord.RES_Approval_Status__c ==> '+oldRecord.RES_Approval_Status__c);
        system.debug('newRecord.IsActive ==> '+newRecord.IsActive);
        system.debug('oldRecord.IsActive ==> '+oldRecord.IsActive);
        if ((newRecord.RES_Approval_Status__c == 'Approved' && newRecord.RES_Approval_Status__c != oldRecord.RES_Approval_Status__c) && 
            (newRecord.IsActive  == true && newRecord.IsActive  != oldRecord.IsActive)) {
                system.debug('return true ==> ');
                return true;
            }
        system.debug('return false ==> ');
        return false;
    }
}