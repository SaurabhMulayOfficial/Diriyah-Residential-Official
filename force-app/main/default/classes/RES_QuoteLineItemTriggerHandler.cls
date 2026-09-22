/**
 * This is QuoteLineItem Trigger Handler class. Call your service/Utility class methods from here. And implement the logic in those classes.
 */

public with sharing class RES_QuoteLineItemTriggerHandler extends RES_BaseTriggerHandler {

    protected override void afterInsert() {
        RES_QuoteLineItemProductHandler.populateQuoteProduct((List<QuoteLineItem>) Trigger.new);
    }

    protected override void afterDelete() {
        RES_QuoteLineItemProductHandler.clearQuoteProduct((List<QuoteLineItem>) Trigger.old, (Map<Id, QuoteLineItem>) Trigger.oldMap);
    }

    protected override void beforeUpdate() {
        RES_QuoteLineItemLockHandler.enforceLock((List<QuoteLineItem>) Trigger.new, (Map<Id, QuoteLineItem>) Trigger.oldMap);
    }
}
