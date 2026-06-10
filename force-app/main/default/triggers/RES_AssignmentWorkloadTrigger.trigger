trigger RES_AssignmentWorkloadTrigger on RES_Assignment_Workload__c (after update) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if(config.RES_Triggers_Off__c == false){  
        new RES_AssignmentWorkloadHandler().run();   
    }
}