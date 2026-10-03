/**
 * @description Service layer managing Contract-driven Account integration workflows.
 * @Created Date : 24/09/2026
 * @Last Modified Date : 24/09/2026
 * @Author : Nitin Marathe
 */
public with sharing class RES_AccountServices {

    public static void handleContractAccountSync(List<Contract> newContracts) {
        if (newContracts == null || newContracts.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        for (Contract ctr : newContracts) {
            if (ctr.AccountId != null) {
                accountIds.add(ctr.AccountId);
            }
        }

        if (accountIds.isEmpty()) {
            return;
        }

        Map<Id, Account> accountMap = new RES_AccountDAOLayer().getAccountsByIds(accountIds);

        List<RES_Integration_Request__e> integrationRequestEventList = new List<RES_Integration_Request__e>();
        for (Id accId : accountIds) {
            Account acc = accountMap.get(accId);
            if (acc == null) {
                continue;
            }

            Boolean isUpdate = String.isNotBlank(acc.RES_External_Key__c);
            String triggerContext = isUpdate ? 'U' : 'I';

            RES_Integration_Request__e req = new RES_Integration_Request__e();
            req.RES_RecordIds__c = String.valueOf(accId);
            req.RES_Request_Method__c = 'GET';
            req.RES_Triggering_Context__c = triggerContext;
            req.RES_Service_Name__c = 'Account_Sync';
            integrationRequestEventList.add(req);
        }

        try {
            if (!integrationRequestEventList.isEmpty()) {
                EventBus.publish(integrationRequestEventList);
            }
        } catch (Exception e) {
            System.debug('Exception publishing Account Integration Request Event: ' + e.getMessage());
        }
    }
}