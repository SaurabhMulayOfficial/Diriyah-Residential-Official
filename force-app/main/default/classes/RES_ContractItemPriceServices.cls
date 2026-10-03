/*
 * Class Name  : RES_ContractItemPriceServices
 * Description : Handles synchronization of Contracts when the required
 *               Contract Item Price records (Unit and Payment Plan) exist.
 *               Triggers Contract synchronization only when both CIP types
 *               are present for the associated Contract.
 */

public with sharing class RES_ContractItemPriceServices {
    public RES_ContractItemPriceServices() {}

    @TestVisible private static List<ContractItemPrice> mockExistingCIPs;
    @TestVisible private static List<Contract> mockContractList;

    public static void syncContracts(List<ContractItemPrice> CIPList){
        if(CIPList.isEmpty())return;

        Set<Id> contractIds = new Set<Id>();
        for(ContractItemPrice cip: CIPList){
            if(cip.ContractId != null){
                if(cip.RES_CIP_Type__c == 'Unit' || cip.RES_CIP_Type__c == 'Payment Plan'){
                    contractIds.add(cip.ContractId);
                }
            }
        }

        if(contractIds.isEmpty())return;

        List<ContractItemPrice> existingCIPs = mockExistingCIPs != null
            ? mockExistingCIPs
            : new RES_ContractItemPriceDAOLayer().getCIPByContractIds(contractIds);

        Map<Id, Boolean> hasUnit = new Map<Id, Boolean>();
        Map<Id, Boolean> hasPaymentPlan = new Map<Id, Boolean>();

        for (ContractItemPrice cip : existingCIPs) {
            if (cip.RES_CIP_Type__c == 'Unit') {
                hasUnit.put(cip.ContractId, true);
            } else if (cip.RES_CIP_Type__c == 'Payment Plan') {
                hasPaymentPlan.put(cip.ContractId, true);
            }
        }

        Set<Id> eligibleContractsToSync = new Set<Id>();

        for (Id contractId : contractIds) {
            if (hasUnit.containsKey(contractId) && hasPaymentPlan.containsKey(contractId)) {
                eligibleContractsToSync.add(contractId);
            }
        }

        if(!eligibleContractsToSync.isEmpty()){
            List<Contract> contractList = mockContractList != null
                ? mockContractList
                : new RES_ContractDAOLayer().getContractsByIds(eligibleContractsToSync);

            try{
                RES_ContractServices.syncContract(contractList, null);
            }catch(Exception e){
                System.debug(e.getMessage());
            }
        }

    }
}