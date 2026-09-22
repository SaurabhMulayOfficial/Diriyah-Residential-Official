/**
 * This is Quote Trigger Handler class. Call your service/Utility class methods from here. And implement the logic in those classes.
 */

public with sharing class RES_QuoteTriggerHandler extends RES_BaseTriggerHandler {

    protected override void beforeUpdate() {
        RES_QuoteCustomerApprovedLockHandler.enforceLock((List<Quote>) Trigger.new, (Map<Id, Quote>) Trigger.oldMap);
    }
}
