public with sharing class RES_ContractItemPriceService {

    // Injected in tests to supply installment data without DB CIP inserts
    @TestVisible
    private static List<ContractItemPrice> testInstallmentOverride;

    public static void updateFinalPaymentOnContract(List<ContractItemPrice> CIPList) {
        if (CIPList == null || CIPList.isEmpty()) return;

        Set<Id> contractIds = new Set<Id>();
        for (ContractItemPrice cip : CIPList) {
            if (cip.ContractId != null) {
                contractIds.add(cip.ContractId);
            }
        }
        if (contractIds.isEmpty()) return;

        List<ContractItemPrice> lineItems = testInstallmentOverride != null
            ? testInstallmentOverride
            : new RES_ContractItemPriceDAOLayer().getInstallmentsByContractIds(contractIds);
        testInstallmentOverride = null;

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
