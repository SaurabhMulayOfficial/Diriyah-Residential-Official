/**
 * @description Stamps the service charge rate and billing frequency onto Service Charge quote lines, taken from the quote's
 * unit (same catalog config RES_ResidentialBundlePricingHook prices the amount from), so documents can refer to them.
 */
public with sharing class RES_ServiceChargeLineService {

    private static final String CIP_TYPE_UNIT = 'Unit';
    private static final String CIP_TYPE_SERVICE_CHARGE = 'Service Charge';

    /** Before insert/update; oldMap is null on insert. Skips lines already stamped whose amount hasn't changed. */
    public static void populateQuoteLines(List<QuoteLineItem> lines, Map<Id, QuoteLineItem> oldMap) {
        Set<Id> productIds = new Set<Id>();
        for (QuoteLineItem line : lines) {
            if (line.Product2Id != null) {
                productIds.add(line.Product2Id);
            }
        }
        if (productIds.isEmpty()) {
            return;
        }
        // RES_CIP_Type__c on the line is a formula, not evaluated yet in a before trigger
        Map<Id, Product2> productsById = new Map<Id, Product2>([SELECT Id, RES_CIP_Type__c FROM Product2 WHERE Id IN :productIds WITH SYSTEM_MODE]);

        List<QuoteLineItem> serviceChargeLines = new List<QuoteLineItem>();
        Map<Id, Id> unitIdByQuoteId = new Map<Id, Id>();
        for (QuoteLineItem line : lines) {
            String cipType = productsById.get(line.Product2Id)?.RES_CIP_Type__c;
            if (cipType == CIP_TYPE_SERVICE_CHARGE && line.QuoteId != null && needsStamp(line, oldMap?.get(line.Id))) {
                serviceChargeLines.add(line);
            } else if (cipType == CIP_TYPE_UNIT && line.QuoteId != null && (line.Quantity ?? 0) > 0) {
                // Lines inserted alongside the unit aren't queryable yet
                unitIdByQuoteId.put(line.QuoteId, line.Product2Id);
            }
        }
        if (serviceChargeLines.isEmpty()) {
            return;
        }

        Set<Id> unresolvedQuoteIds = new Set<Id>();
        for (QuoteLineItem line : serviceChargeLines) {
            if (!unitIdByQuoteId.containsKey(line.QuoteId)) {
                unresolvedQuoteIds.add(line.QuoteId);
            }
        }
        if (!unresolvedQuoteIds.isEmpty()) {
            // Quantity > 0 skips the outgoing unit of a unit swap
            for (QuoteLineItem unitLine : [
                SELECT QuoteId, Product2Id FROM QuoteLineItem
                WHERE QuoteId IN :unresolvedQuoteIds AND Product2.RES_CIP_Type__c = :CIP_TYPE_UNIT AND Quantity > 0
                WITH SYSTEM_MODE
            ]) {
                unitIdByQuoteId.put(unitLine.QuoteId, unitLine.Product2Id);
            }
        }

        Map<Id, RES_ResidentialBundlePricingHook.ServiceChargeBreakdown> breakdownByUnitId =
            RES_ResidentialBundlePricingHook.serviceChargeBreakdowns(new Set<Id>(unitIdByQuoteId.values()));
        for (QuoteLineItem line : serviceChargeLines) {
            RES_ResidentialBundlePricingHook.ServiceChargeBreakdown breakdown = breakdownByUnitId.get(unitIdByQuoteId.get(line.QuoteId));
            if (breakdown != null) {
                line.RES_Service_Charge_Rate__c = breakdown.rate;
                line.RES_Service_Charge_Frequency__c = breakdown.billingFrequency;
            }
        }
    }

    private static Boolean needsStamp(QuoteLineItem line, QuoteLineItem oldLine) {
        return oldLine == null
            || line.RES_Service_Charge_Rate__c == null
            || line.RES_Service_Charge_Frequency__c == null
            || line.RES_Service_Charge_Amount__c != oldLine.RES_Service_Charge_Amount__c;
    }
}
