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

    public static void updateFinalPaymentOnContract(List<ContractItemPrice> CIPList) {
        if (CIPList == null || CIPList.isEmpty()) return;

        Set<Id> contractIds = new Set<Id>();
        for (ContractItemPrice cip : CIPList) {
            if (cip.ContractId != null) {
                contractIds.add(cip.ContractId);
            }
        }
        if (contractIds.isEmpty()) return;

        List<ContractItemPrice> lineItems = mockExistingCIPs != null
            ? mockExistingCIPs
            : new RES_ContractItemPriceDAOLayer().getInstallmentsByContractIds(contractIds);
        mockExistingCIPs = null;

        Map<Id, ContractItemPrice> lastInstallmentByContract = new Map<Id, ContractItemPrice>();
        Map<Id, Integer> maxNumberByContract = new Map<Id, Integer>();

        for (ContractItemPrice cip : lineItems) {
            String productName = cip.RES_Product__r != null ? cip.RES_Product__r.Name : cip.Name;
            Integer installmentNumber = parseInstallmentNumber(productName);
            Integer currentMax = maxNumberByContract.get(cip.ContractId);
            if (currentMax == null || installmentNumber > currentMax) {
                maxNumberByContract.put(cip.ContractId, installmentNumber);
                lastInstallmentByContract.put(cip.ContractId, cip);
            }
        }

        // Query current Contract values to avoid unnecessary updates
        Map<Id, Contract> currentContracts = new Map<Id, Contract>(
            [SELECT Id, RES_Final_Payment__c FROM Contract WHERE Id IN :contractIds]
        );

        List<Contract> contractsToUpdate = new List<Contract>();
        for (Id contractId : contractIds) {
            Decimal newPrice = lastInstallmentByContract.containsKey(contractId)
                ? lastInstallmentByContract.get(contractId).Price
                : null;

            Contract current = currentContracts.get(contractId);
            if (current != null && current.RES_Final_Payment__c != newPrice) {
                contractsToUpdate.add(new Contract(Id = contractId, RES_Final_Payment__c = newPrice));
            }
        }

        if (!contractsToUpdate.isEmpty()) {
            update contractsToUpdate;
        }
    }

    private static Integer parseInstallmentNumber(String name) {
        if (String.isBlank(name)) return 0;
        String lastToken = name.substringAfterLast(' ').trim();
        if (lastToken.isNumeric()) {
            return Integer.valueOf(lastToken);
        }
        return 0;
    }


}