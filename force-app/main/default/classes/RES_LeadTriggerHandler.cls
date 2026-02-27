/**
 * This is Lead Trigger Handler class. Call your service/Utility class methods from here. And implement the logic in those classes.
 */

public with sharing class RES_LeadTriggerHandler extends RES_BaseTriggerHandler {

    protected override void beforeInsert() {
        System.debug('Before Insert Logic here');
        RES_LeadServices.setUpdateSLATimeOnLead((list<lead>)Trigger.new, null);
    }

    protected override void beforeUpdate() {
        System.debug('Before Update Logic here');
        RES_LeadServices.setUpdateSLATimeOnLead((list<lead>)Trigger.new, (Map<id, lead>)Trigger.oldMap);
    }
    

    protected override void beforeDelete() {
        System.debug('Before Delete Logic here');
    }

    protected override void afterInsert() {
        System.debug('After Insert Logic here');
    }

    protected override void afterUpdate() {
        System.debug('After Update Logic here');
    }
    
    protected override void afterDelete() {
        System.debug('After Delete Logic here');
    }
    

    protected override void afterUndelete() {
        System.debug('After Undelete Logic here');
    }

}