/**
 * @description Service layer for Installment-related business operations.
 *              Provides reusable methods for processing and synchronizing
 *              Installment records.
 *
 * @author Saurabh Mulay
 */
public with sharing class RES_InstallmentServices {
    public RES_InstallmentServices() {}

    public static void syncInstallments(List<RES_Installment__c> installments, Map<Id, RES_Installment__c> oldMap) {
        List<RES_Installment__c> installmentsToSync = new List<RES_Installment__c>();

        RES_SAP_Integration_Config__mdt installmentMDT =
            new RES_SAPIntegrationConfigDAO()
                .getSAPIntegrationConfigByDeveloperName('Installments');

        if (installmentMDT == null || String.isBlank(installmentMDT.RES_Sync_Fields__c)) {
            throw new RES_IntegrationException(
                'SAP Integration Config is Not available for "Installments", create and provide at least 1 field for change.'
            );
        }

        List<String> syncFieldLst = installmentMDT.RES_Sync_Fields__c.split(',');
        Set<String> syncFields = new Set<String>();

        for (String field : syncFieldLst) {
            if (String.isNotBlank(field)) {
                syncFields.add(field.trim());
            }
        }

        String triggerContext = (oldMap == null ? 'I' : 'U');

        for (RES_Installment__c installment : installments) {
            if (oldMap == null) {
                installmentsToSync.add(installment);
            } else if (isInstallmentChanged(installment, oldMap.get(installment.Id), syncFields) && installment.RES_Last_Sync_DateTime__c != null) {
                installmentsToSync.add(installment);
            }
        }

        if (installmentsToSync.isEmpty()) {
            return;
        }

        List<RES_Integration_Request__e> integrationRequestEventList = new List<RES_Integration_Request__e>();

        for (RES_Installment__c inst : installmentsToSync) {
            RES_Integration_Request__e req = new RES_Integration_Request__e();
            req.RES_RecordIds__c = String.valueOf(inst.Id);
            req.RES_Request_Method__c = 'GET';
            req.RES_Triggering_Context__c = triggerContext;
            req.RES_Service_Name__c = 'Installments';
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

    private static Boolean isInstallmentChanged(RES_Installment__c newRecord, RES_Installment__c oldRecord, Set<String> syncFields) {
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
}