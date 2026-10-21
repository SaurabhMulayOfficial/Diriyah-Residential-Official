/**
 * @description Single place for the installment due date rule shared by payment plan creation, the configurator
 * preview, quote lines and contract item prices (copied from the quote line):
 *   Off-Plan - fixed when the payment plan is created: Valid From + condition months/days (stored on the installment product).
 *   On-Plan  - dynamic: the date the plan is configured on a quote + condition months/days.
 */
public with sharing class RES_InstallmentDueDateService {

    public static final String PHASE_ON_PLAN = 'On-Plan';
    public static final String PHASE_OFF_PLAN = 'Off-Plan';

    public static Date dueDate(Date anchor, Decimal months, Decimal days) {
        if (anchor == null || (months == null && days == null)) {
            return null;
        }
        return anchor.addMonths(months == null ? 0 : months.intValue()).addDays(days == null ? 0 : days.intValue());
    }

    // Due date of an installment configured on configurationDate, given its payment plan's development phase
    public static Date dueDateOnConfiguration(Product2 installment, String developmentPhase, Date configurationDate, Date planValidFrom) {
        if (developmentPhase == PHASE_ON_PLAN) {
            return dueDate(configurationDate, installment.RES_Condition_Months__c, installment.RES_Condition_Days__c);
        }
        // Plans created before Off-Plan due dates were stored fall back to Valid From + condition months/days
        return installment.RES_Instalment_DueDate__c
            ?? dueDate(planValidFrom ?? configurationDate, installment.RES_Condition_Months__c, installment.RES_Condition_Days__c);
    }

    /** Sets RES_Installment_Due_Date__c on new installment quote lines (before insert). */
    public static void populateQuoteLineDueDates(List<QuoteLineItem> lines) {
        Set<Id> productIds = new Set<Id>();
        for (QuoteLineItem line : lines) {
            if (line.Product2Id != null && line.RES_Installment_Due_Date__c == null) {
                productIds.add(line.Product2Id);
            }
        }
        if (productIds.isEmpty()) {
            return;
        }

        Map<Id, ProductRelatedComponent> componentByInstallmentId = new Map<Id, ProductRelatedComponent>();
        for (ProductRelatedComponent component : [
            SELECT ChildProductId, ChildProduct.RES_Condition_Months__c, ChildProduct.RES_Condition_Days__c, ChildProduct.RES_Instalment_DueDate__c,
                   ParentProduct.AvailabilityDate, ParentProduct.RES_Business_Entity__r.RES_Development_Phase__c
            FROM ProductRelatedComponent
            WHERE ChildProductId IN :productIds AND ChildProduct.RES_CIP_Type__c = 'Installment'
            WITH SYSTEM_MODE
        ]) {
            componentByInstallmentId.put(component.ChildProductId, component);
        }

        Date configurationDate = Date.today();
        for (QuoteLineItem line : lines) {
            ProductRelatedComponent component = componentByInstallmentId.get(line.Product2Id);
            if (component == null || line.RES_Installment_Due_Date__c != null) {
                continue;
            }
            line.RES_Installment_Due_Date__c = dueDateOnConfiguration(
                component.ChildProduct,
                component.ParentProduct.RES_Business_Entity__r?.RES_Development_Phase__c,
                configurationDate,
                component.ParentProduct.AvailabilityDate?.date()
            );
        }
    }

    /** Sets RES_Installment_Due_Date__c on new contract item prices (before insert) from the matching installment line on the contract's quote. */
    public static void populateContractItemPriceDueDates(List<ContractItemPrice> cips) {
        Set<Id> contractIds = new Set<Id>();
        Set<Id> itemIds = new Set<Id>();
        for (ContractItemPrice cip : cips) {
            if (cip.ContractId != null && cip.ItemId != null && cip.RES_Installment_Due_Date__c == null) {
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
        Map<String, Date> dueDateByQuoteAndProduct = new Map<String, Date>();
        if (!quoteIdByContractId.isEmpty()) {
            for (QuoteLineItem line : [
                SELECT QuoteId, Product2Id, RES_Installment_Due_Date__c FROM QuoteLineItem
                WHERE QuoteId IN :quoteIdByContractId.values() AND Product2Id IN :itemIds AND RES_Installment_Due_Date__c != null
                WITH SYSTEM_MODE
            ]) {
                dueDateByQuoteAndProduct.put(line.QuoteId + '|' + line.Product2Id, line.RES_Installment_Due_Date__c);
            }
        }

        // No dated quote line (e.g. contract without a quote): fall back to the same rule the quote line uses
        List<QuoteLineItem> fallbackLines = new List<QuoteLineItem>();
        List<ContractItemPrice> fallbackCips = new List<ContractItemPrice>();
        for (ContractItemPrice cip : cips) {
            if (cip.ContractId == null || cip.ItemId == null || cip.RES_Installment_Due_Date__c != null) {
                continue;
            }
            Date dueDate = dueDateByQuoteAndProduct.get(quoteIdByContractId.get(cip.ContractId) + '|' + cip.ItemId);
            if (dueDate != null) {
                cip.RES_Installment_Due_Date__c = dueDate;
            } else if (cip.ItemId.getSObjectType() == Product2.SObjectType) {
                fallbackLines.add(new QuoteLineItem(Product2Id = cip.ItemId));
                fallbackCips.add(cip);
            }
        }
        if (!fallbackLines.isEmpty()) {
            populateQuoteLineDueDates(fallbackLines);
            for (Integer i = 0; i < fallbackLines.size(); i++) {
                fallbackCips[i].RES_Installment_Due_Date__c = fallbackLines[i].RES_Installment_Due_Date__c;
            }
        }
    }

    /** Development phase and Valid From of a payment plan, via its catalog. */
    public static Product2 planWithPhase(Id planProductId) {
        List<Product2> plans = [
            SELECT Id, Name, AvailabilityDate, RES_Business_Entity__r.RES_Development_Phase__c
            FROM Product2 WHERE Id = :planProductId
            WITH SYSTEM_MODE LIMIT 1
        ];
        return plans.isEmpty() ? null : plans[0];
    }
}
