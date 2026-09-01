trigger RES_QuoteLineItemTrigger on QuoteLineItem (before update) {
    RES_QuoteLineItemLockHandler.enforceLock(Trigger.new, Trigger.oldMap);
}
