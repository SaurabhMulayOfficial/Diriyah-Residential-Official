trigger RES_QuoteTrigger on Quote (before update) {
    RES_QuoteCustomerApprovedLockHandler.enforceLock(Trigger.new, Trigger.oldMap);
}
