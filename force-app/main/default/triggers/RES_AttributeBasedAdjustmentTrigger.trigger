trigger RES_AttributeBasedAdjustmentTrigger on AttributeBasedAdjustment (before insert, before update, after insert, after update) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if (config.RES_Triggers_Off__c == false) {
        new RES_AttrBasedAdjTriggerHandler().run();
    }
}
