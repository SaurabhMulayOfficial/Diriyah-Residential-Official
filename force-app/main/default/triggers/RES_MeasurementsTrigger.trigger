trigger RES_MeasurementsTrigger on RES_Measurement__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if(config.RES_Triggers_Off__c == false){  
        new RES_MeasurementTriggerHandler().run();   
    }
}