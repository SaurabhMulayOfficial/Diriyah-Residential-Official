trigger RES_ReviewApprovalWorkItemTrigger on RES_Review_Approval_Work_Item__e (after insert) {
    RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
    if(config.RES_Triggers_Off__c == false){  
        new RES_ReviewApprovalWorkItemHandler().run();   
    }
}