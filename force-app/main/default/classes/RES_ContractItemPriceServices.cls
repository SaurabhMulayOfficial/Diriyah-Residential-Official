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
    @TestVisible private static List<String> finalPaymentUpdateErrors = new List<String>();

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
            if (cip.RES_Product__r == null || cip.RES_Product__r.RES_Sequence__c == null) continue;
            Integer sequence = cip.RES_Product__r.RES_Sequence__c.intValue();
            Integer currentMax = maxNumberByContract.get(cip.ContractId);
            if (currentMax == null || sequence > currentMax) {
                maxNumberByContract.put(cip.ContractId, sequence);
                lastInstallmentByContract.put(cip.ContractId, cip);
            }
        }

        // Query current Contract values to avoid unnecessary updates
       Map<Id, Contract> currentContracts = new RES_ContractDAOLayer().getContractsForFinalPayment(contractIds);

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
            // Final Payment is a system-calculated value, so it is written in explicit system
            // mode (same convention as RES_OpportunityStageUpdateValidation) and does not depend on
            // the running user's field access. Partial-success DML: a failure here must never
            // roll back the Contract Item Price insert that triggered it (e.g. the installment
            // generator's bulk insert), so failures are captured instead of thrown.
            finalPaymentUpdateErrors = new List<String>();
            List<Database.SaveResult> saveResults =
                Database.update(contractsToUpdate, false, AccessLevel.SYSTEM_MODE);
            for (Integer index = 0; index < saveResults.size(); index++) {
                if (!saveResults[index].isSuccess()) {
                    String errorMessage = 'Final Payment update failed for Contract '
                        + contractsToUpdate[index].Id + ': '
                        + saveResults[index].getErrors()[0].getMessage();
                    finalPaymentUpdateErrors.add(errorMessage);
                    System.debug(LoggingLevel.ERROR, errorMessage);
                }
            }
        }
    }

    /**
     * Before insert: the Service Charge quote line is unpriced (kept out of quote totals), so its contract item price takes the
     * stored RES_Service_Charge_Amount__c instead, along with the line's service charge rate and frequency.
     */
    public static void populateServiceChargePrices(List<ContractItemPrice> cips) {
        Set<Id> contractIds = new Set<Id>();
        Set<Id> itemIds = new Set<Id>();
        for (ContractItemPrice cip : cips) {
            if (cip.ContractId != null && cip.ItemId != null) {
                contractIds.add(cip.ContractId);
                itemIds.add(cip.ItemId);
            }
        }
        if (contractIds.isEmpty()) {
            return;
        }

        Map<Id, Id> quoteIdByContractId = new Map<Id, Id>();
        for (Contract contract : [SELECT Id, SourceQuoteId, RES_Quote_Id__c FROM Contract WHERE Id IN :contractIds WITH SYSTEM_MODE]) {
            Id quoteId = contract.SourceQuoteId ?? contract.RES_Quote_Id__c;
            if (quoteId != null) {
                quoteIdByContractId.put(contract.Id, quoteId);
            }
        }
        if (quoteIdByContractId.isEmpty()) {
            return;
        }

        Map<String, QuoteLineItem> lineByQuoteAndProduct = new Map<String, QuoteLineItem>();
        for (QuoteLineItem line : [
            SELECT QuoteId, Product2Id, RES_Service_Charge_Amount__c, RES_Service_Charge_Rate__c, RES_Service_Charge_Frequency__c FROM QuoteLineItem
            WHERE QuoteId IN :quoteIdByContractId.values() AND Product2Id IN :itemIds AND RES_Service_Charge_Amount__c != null
            WITH SYSTEM_MODE
        ]) {
            lineByQuoteAndProduct.put(line.QuoteId + '|' + line.Product2Id, line);
        }

        for (ContractItemPrice cip : cips) {
            QuoteLineItem line = lineByQuoteAndProduct.get(quoteIdByContractId.get(cip.ContractId) + '|' + cip.ItemId);
            if (line == null) {
                continue;
            }
            if (cip.Price == null || cip.Price == 0) {
                cip.Price = line.RES_Service_Charge_Amount__c;
            }
            cip.RES_Service_Charge_Rate__c = cip.RES_Service_Charge_Rate__c ?? line.RES_Service_Charge_Rate__c;
            cip.RES_Service_Charge_Frequency__c = cip.RES_Service_Charge_Frequency__c ?? line.RES_Service_Charge_Frequency__c;
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