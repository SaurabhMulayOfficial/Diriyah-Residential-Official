/**
 * @description Orders installment quote lines by their installment sequence so the sales transaction line table lists them ascending.
 */
public with sharing class RES_QuoteLineSortOrderService {

    /** Sets SortOrder from Product2.RES_Sequence__c on new installment quote lines (before insert). */
    public static void populateInstallmentSortOrder(List<QuoteLineItem> lines) {
        Set<Id> productIds = new Set<Id>();
        for (QuoteLineItem line : lines) {
            if (line.Product2Id != null && line.SortOrder == null) {
                productIds.add(line.Product2Id);
            }
        }
        if (productIds.isEmpty()) {
            return;
        }

        Map<Id, Product2> installmentsById = new Map<Id, Product2>([
            SELECT Id, RES_Sequence__c FROM Product2
            WHERE Id IN :productIds AND RES_Sequence__c != null
            WITH SYSTEM_MODE
        ]);
        for (QuoteLineItem line : lines) {
            Product2 installment = installmentsById.get(line.Product2Id);
            if (installment != null && line.SortOrder == null) {
                line.SortOrder = installment.RES_Sequence__c.intValue();
            }
        }
    }
}
