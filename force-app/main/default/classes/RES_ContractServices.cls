/**
 * @description Service layer for Contract-related business operations.
 *              Provides reusable methods for processing and synchronizing
 *              Contract records.
 *
 * @author Saurabh Mulay
 */
public with sharing class RES_ContractServices {
    public RES_ContractServices() {}

    public static void syncContract(List<Contract> contracts, Map<Id, Contract> oldMap) {
        List<Contract> contractsToSync_insert = new List<Contract>();
        List<Contract> contractsToSync_update = new List<Contract>();
        List<Contract> contractsToSync_Termination = new List<Contract>();

        RES_SAP_Integration_Config__mdt contractMDT =
            new RES_SAPIntegrationConfigDAO()
                .getSAPIntegrationConfigByDeveloperName('Sales_Contract_Creation');

        if (contractMDT == null || String.isBlank(contractMDT.RES_Sync_Fields__c)) {
            throw new RES_IntegrationException(
                'SAP Integration Config is Not available for "Contract", create and provide at least 1 field for change.'
            );
        }

        List<String> syncFieldLst = contractMDT.RES_Sync_Fields__c.split(',');
        Set<String> syncFields = new Set<String>();

        for (String field : syncFieldLst) {
            if (String.isNotBlank(field)) {
                syncFields.add(field.trim());
            }
        }

        for (Contract contract : contracts) {
            if (oldMap == null) {
                contractsToSync_insert.add(contract);
            }

            else if(isContractChanged(contract, oldMap.get(contract.Id), syncFields) && contract.RES_Last_Sync_DateTime__c != null){
                if(isStatusChanged(contract, oldMap.get(contract.Id))){
                    contractsToSync_Termination.add(contract);
                }
                else{
                    contractsToSync_update.add(contract);
                }   
            }
        }

        if (contractsToSync_insert.isEmpty() && contractsToSync_update.isEmpty() && contractsToSync_Termination.isEmpty()) {
            return;
        }

        String triggerContext = (oldMap == null ? 'I' : 'U');

        List<RES_Integration_Request__e> integrationRequestEventList = new List<RES_Integration_Request__e>();
        for (Contract c : contractsToSync_insert) {
            RES_Integration_Request__e req = new RES_Integration_Request__e();
            req.RES_RecordIds__c = String.valueOf(c.Id);
            req.RES_Request_Method__c = 'GET';
            req.RES_Triggering_Context__c = triggerContext;
            req.RES_Service_Name__c = 'Sales_Contract_Creation';
            integrationRequestEventList.add(req);
        }

        for (Contract c : contractsToSync_update) {
            RES_Integration_Request__e req = new RES_Integration_Request__e();
            req.RES_RecordIds__c = String.valueOf(c.Id);
            req.RES_Request_Method__c = 'GET';
            req.RES_Triggering_Context__c = triggerContext;
            req.RES_Service_Name__c = 'Sales_Contract_Update';
            integrationRequestEventList.add(req);
        }

        for (Contract c : contractsToSync_update) {
            RES_Integration_Request__e req = new RES_Integration_Request__e();
            req.RES_RecordIds__c = String.valueOf(c.Id);
            req.RES_Request_Method__c = 'GET';
            req.RES_Triggering_Context__c = triggerContext;
            req.RES_Service_Name__c = 'Sales_Contract_Termination';
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

    private static boolean isStatusChanged(Contract newRecord, Contract oldRecord){
        if(newRecord.Status != oldRecord.Status && newRecord.Status == 'Contract Terminated'){
            return true;
        }

        return false;
    }

    private static Boolean isContractChanged(Contract newRecord, Contract oldRecord, Set<String> syncFields) {
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