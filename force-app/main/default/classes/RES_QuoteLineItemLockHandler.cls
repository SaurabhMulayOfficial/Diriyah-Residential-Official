/**
 * DIR-869 / DIR-1612 / DIR-1777: Replaces the RES_Customer_Approved_QLI_Locked validation rule.
 *
 * Locks every genuinely user-editable field on a Customer Approved Quote's line items. Fields
 * that aren't user-updateable to begin with (isCalculated() or !isUpdateable() - e.g.
 * NetUnitPrice, NetTotalPrice, Subtotal, TotalPrice, TotalLineAmount, PriceWaterfallIdentifier)
 * are exempt, mirroring the pattern RES_QuoteCustomerApprovedLockHandler already uses on Quote
 * itself. ValidationResult and ConstraintEngineNodeStatus__c are ALSO exempt via EXEMPT_FIELDS
 * even though they're FLS-updateable, because they're per-line engine-status fields (not business
 * data) that the pricing engine rewrites on every recalculation - confirmed live: repricing an
 * existing swap quote (Quote 0Q09X00000DT31RSAT) still returned
 * FIELD_CUSTOM_VALIDATION_EXCEPTION from this handler on its -1 quantity line until this field
 * was added. Exempting these fields can't reopen a path for unauthorized edits - it only stops
 * this lock from also blocking the pricing engine's own recalculation writes, which was leaving
 * Customer Approved quotes permanently stuck at CalculationStatus = SaveFailedOrIncomplete
 * (DIR-1777: Create Order then refuses with "the calculation status of the quote is invalid").
 *
 * UnitPrice is handled separately (SWAP_LINE_EXEMPT_FIELDS, not EXEMPT_FIELDS): confirmed live on
 * that same swap quote (0Q09X00000DT31RSAT) that the recalculation needs to write UnitPrice on
 * BOTH lines of the swap pair - first the -1 "outgoing" line (left at UnitPrice = null alongside
 * a stale ListPrice/TotalPrice), then, once that was exempted, the +1 "incoming" line too (left at
 * UnitPrice = 0 while its own NetUnitPrice/TotalPrice already showed the correct 61426502 - i.e.
 * genuinely stale/inconsistent data the engine is reconciling, not a fresh user edit). Unlike
 * ValidationResult/ConstraintEngineNodeStatus__c, UnitPrice is genuine pricing data, so it is NOT
 * blanket-exempt on every Customer Approved line - it is only let through on lines that belong to
 * a Quote which itself has at least one negative-quantity line (queried across ALL of that
 * quote's line items, not just the ones in this trigger batch, since the -1/+1 pair can be
 * updated in separate transactions). A negative-quantity line only exists as an artifact of the
 * platform's own swap mechanism (Quantity itself stays fully locked, so a user can't create one),
 * so this scopes the carve-out to swap quotes specifically - an ordinary approved quote's UnitPrice
 * (the one an approver actually priced) stays locked, so this can't reopen a path for post-approval
 * price tampering.
 *
 * RES_QuoteCancellationService queries QuoteLineItem to find Product2 records to release but
 * never writes to QuoteLineItem itself (confirmed by reading its source), so no bypass is needed
 * here for that flow.
 */
public without sharing class RES_QuoteLineItemLockHandler {

    private static final String LOCKED_STATUS = 'Customer Approved';
    private static final String ERROR_MESSAGE = 'This quote\'s line items are locked because the quote has been Customer Approved.';

    // Fields Salesforce itself mutates on every save regardless of what the user/process touched.
    private static final Set<String> SYSTEM_FIELDS = new Set<String>{
        'id', 'isdeleted', 'createddate', 'createdbyid',
        'lastmodifieddate', 'lastmodifiedbyid', 'systemmodstamp',
        'lastvieweddate', 'lastreferenceddate'
    };

    // DIR-1777: per-line engine-status fields the pricing engine rewrites on every recalculation,
    // same category as Quote.ValidationResult (see RES_QuoteCustomerApprovedLockHandler) - FLS-
    // updateable so isUpdateable() alone doesn't exempt them, but they carry calculation/config
    // status, not business data, so exempting them can't reopen a path for unauthorized edits.
    @TestVisible
    private static final Set<String> EXEMPT_FIELDS = new Set<String>{
        'validationresult',
        'constraintenginenodestatus__c'
    };

    // DIR-1777: UnitPrice the engine needs to reconcile on a swap quote's line items - see class
    // doc. Only exempt when the parent Quote itself has a negative-quantity line (a swap).
    @TestVisible
    private static final Set<String> SWAP_LINE_EXEMPT_FIELDS = new Set<String>{
        'unitprice'
    };

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
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.QuoteLineItem.fields.getMap();

        Set<Id> swapQuoteIds = new Set<Id>();
        for (QuoteLineItem qli : new RES_QuoteLineItemDAO().getQuoteLineItemQuantitiesByQuoteIds(quoteIds)) {
            if (qli.Quantity != null && qli.Quantity < 0) {
                swapQuoteIds.add(qli.QuoteId);
            }
        }

        for (QuoteLineItem newQli : newItems) {
            QuoteLineItem oldQli = oldMap.get(newQli.Id);
            if (oldQli == null) {
                continue;
            }
            Quote parent = quotesById.get(newQli.QuoteId);
            if (parent == null || parent.Status != LOCKED_STATUS) {
                continue;
            }

            Boolean isSwapLine = swapQuoteIds.contains(newQli.QuoteId);

            for (String fieldName : fieldMap.keySet()) {
                if (SYSTEM_FIELDS.contains(fieldName) || EXEMPT_FIELDS.contains(fieldName)) {
                    continue;
                }
                if (isSwapLine && SWAP_LINE_EXEMPT_FIELDS.contains(fieldName)) {
                    continue;
                }

                Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
                if (dfr.isCalculated() || !dfr.isUpdateable()) {
                    continue; // platform/pricing-engine-managed fields aren't genuine user edits
                }

                if (newQli.get(fieldName) != oldQli.get(fieldName)) {
                    newQli.addError(ERROR_MESSAGE);
                    break;
                }
            }
        }
    }

    private static Boolean isSwitchedOff() {
        RES_Config_Switch__c cs = RES_Config_Switch__c.getInstance();
        return cs != null && cs.RES_Triggers_Off__c == true;
    }
}
