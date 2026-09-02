/**
 * DIR-869 / DIR-1612: Replaces the RES_Customer_Approved_QLI_Locked validation rule.
 *
 * Locks every line item on a Customer Approved Quote - no exemptions. RES_QuoteCancellationService
 * queries QuoteLineItem to find Product2 records to release but never writes to QuoteLineItem
 * itself (confirmed by reading its source), so no bypass is needed here.
 */
public without sharing class RES_QuoteLineItemLockHandler {

    private static final String LOCKED_STATUS = 'Customer Approved';
    private static final String ERROR_MESSAGE = 'This quote\'s line items are locked because the quote has been Customer Approved.';

    public static void enforceLock(List<QuoteLineItem> newItems, Map<Id, QuoteLineItem> oldMap) {
        if (isSwitchedOff() || oldMap == null) {
            return;
        }

        Set<Id> quoteIds = new Set<Id>();
        for (QuoteLineItem qli : newItems) {
            if (qli.QuoteId != null) {
                quoteIds.add(qli.QuoteId);
            }
        }
        if (quoteIds.isEmpty()) {
            return;
        }

        Map<Id, Quote> quotesById = new RES_QuoteDAOLayer().getQuotesByIds(quoteIds);

        for (QuoteLineItem newQli : newItems) {
            if (oldMap.get(newQli.Id) == null) {
                continue;
            }
            Quote parent = quotesById.get(newQli.QuoteId);
            if (parent != null && parent.Status == LOCKED_STATUS) {
                newQli.addError(ERROR_MESSAGE);
            }
        }
    }

    private static Boolean isSwitchedOff() {
        RES_Config_Switch__c cs = RES_Config_Switch__c.getInstance();
        return cs != null && cs.RES_Triggers_Off__c == true;
    }
}
