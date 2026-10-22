/**
 * @description Service layer for Contract-related business operations.
 *              Provides reusable methods for processing and synchronizing
 *              Contract records.
 *
 * @author Saurabh Mulay
 */
public with sharing class RES_ContractServices {

    // Approval Status values that are allowed to fire Sales_Contract_Update
    private static final Set<String> UPDATE_SYNC_APPROVAL_STATUSES = new Set<String>{
        'Finance Approved', 'Pending ED Treasury', 'Pending GCEO', 'Pending CBDO'
    };
    public RES_ContractServices() {}

    // Customer Signed By = Person Account's own contact, or for a Business Account its first-created Contact (no primary flag exists);
    // runs on create only and always overwrites any pre-set value (a Contact is only written when one is found)
    public static void populateCustomerSignedBy(List<Contract> contracts) {
        Set<Id> accountIds = new Set<Id>();
        for (Contract c : contracts) {
            if (c.AccountId != null) {
                accountIds.add(c.AccountId);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }

        Map<Id, Id> contactIdByAccountId = new Map<Id, Id>();
        for (Account acc : new RES_AccountDAOLayer().getAccountsWithPersonContactByIds(accountIds).values()) {
            if (acc.IsPersonAccount) {
                contactIdByAccountId.put(acc.Id, acc.PersonContactId);
            }
        }
        Map<Id, List<Contact>> contactsByAccountId = new RES_ContactDAOLayer().getContactsByAccountIds(accountIds);
        for (Id accountId : contactsByAccountId.keySet()) {
            if (!contactIdByAccountId.containsKey(accountId) && !contactsByAccountId.get(accountId).isEmpty()) {
                contactIdByAccountId.put(accountId, contactsByAccountId.get(accountId)[0].Id);
            }
        }

        for (Contract c : contracts) {
            Id contactId = c.AccountId != null ? contactIdByAccountId.get(c.AccountId) : null;
            if (contactId != null) {
                c.CustomerSignedId = contactId;
            }
        }
    }

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
                if(contract.Account != null && contract.Account.RES_External_Key__c == null){
                    continue;
                }
                contractsToSync_insert.add(contract);
            } 
            else if (oldMap.get(contract.Id) != null
                && oldMap.get(contract.Id).Status == 'Pending Cancellation Approval'
                && contract.Status == 'Activated') {
                // Cancellation request was rejected/reverted; nothing to sync to SAP
                continue;
            }
            else if (oldMap.get(contract.Id) != null
                && oldMap.get(contract.Id).Status != 'Pending Cancellation Approval'
                && contract.Status == 'Pending Cancellation Approval') {
                // Moved to Pending Cancellation Approval: send Sales_Contract_Termination instead of Sales_Contract_Update
                if (contract.RES_Last_Sync_DateTime__c != null && String.isNotBlank(contract.RES_External_ID__c)) {
                    contractsToSync_Termination.add(contract);
                }
                continue;
            }
            else if (isContractChanged(contract, oldMap.get(contract.Id), syncFields)
                && contract.RES_Last_Sync_DateTime__c != null
                && String.isNotBlank(contract.RES_External_ID__c)) {
                if (isStatusChanged(contract, oldMap.get(contract.Id))) {
                    contractsToSync_Termination.add(contract);
                } else if (contract.RES_Approval_Status__c != oldMap.get(contract.Id).RES_Approval_Status__c
                    && !UPDATE_SYNC_APPROVAL_STATUSES.contains(contract.RES_Approval_Status__c)) {
                    // Approval Status changed to a value that must not trigger Sales_Contract_Update
                    continue;
                } else {
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

        for (Contract c : contractsToSync_Termination) {
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

    public class ContractTerminationRequest {
        @InvocableVariable(label='Contract Id' required=true)
        public Id contractId;
    }

    @InvocableMethod(label='Sync Contract Termination' description='Fires Sales_Contract_Termination integration events for the given Contract Ids')
    public static void syncContractTermination(List<ContractTerminationRequest> requests) {
        List<RES_Integration_Request__e> integrationRequestEventList = new List<RES_Integration_Request__e>();
        for (ContractTerminationRequest request : requests) {
            RES_Integration_Request__e req = new RES_Integration_Request__e();
            Id contractId = request.contractId;
            req.RES_RecordIds__c = String.valueOf(contractId);
            req.RES_Request_Method__c = 'GET';
            req.RES_Triggering_Context__c = 'U';
            req.RES_Service_Name__c = 'Sales_Contract_Termination';
            integrationRequestEventList.add(req);
        }
        try {
            if (!integrationRequestEventList.isEmpty()) {
                EventBus.publish(integrationRequestEventList);
            }
        } catch (Exception e) {
            System.debug('Exception Firing Integration Request Event for Termination: ' + e.getMessage());
        }
    }

    private static boolean isStatusChanged(Contract newRecord, Contract oldRecord){
        if(newRecord.Status != oldRecord.Status && newRecord.Status == 'Canceled' && newRecord.RES_Approval_Status__c == 'Approved'){
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