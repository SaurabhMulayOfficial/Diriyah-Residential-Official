trigger RES_QuoteLineItemTrigger on QuoteLineItem (after insert, after delete, before update) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();

    if(config.RES_Triggers_Off__c == false){
        // After Insert: Populate Quote Product field when Residential Unit is added
        if (Trigger.isAfter && Trigger.isInsert) {
            RES_QuoteLineItemProductHandler.populateQuoteProduct(Trigger.new);
        }

        // After Delete: Clear or reassign Quote Product field when QuoteLineItem is removed
        if (Trigger.isAfter && Trigger.isDelete) {
            RES_QuoteLineItemProductHandler.clearQuoteProduct(Trigger.old, Trigger.oldMap);
        }

        // Before Update: Enforce lock on QuoteLineItems
        if (Trigger.isBefore && Trigger.isUpdate) {
            RES_QuoteLineItemLockHandler.enforceLock(Trigger.new, Trigger.oldMap);
        }
    }
}
