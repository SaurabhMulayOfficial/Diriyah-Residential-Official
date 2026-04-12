/**
 * This is Lead Trigger Handler class. Call your service/Utility class methods from here. And implement the logic in those classes.
 */

public with sharing class RES_LeadTriggerHandler extends RES_BaseTriggerHandler {

    protected override void beforeInsert() {
        RES_LeadServices.setUpdateSLATimeOnLead((list<lead>)Trigger.new, null, false, null);
        RES_LeadServices.selectLeadRecordType((list<lead>) Trigger.new);
        RES_LeadServices.applyDeduplicationRules((list<lead>) Trigger.new);
    }

    protected override void afterInsert(){
        RES_LeadServices.processDeduplicationResults();
    }

    protected override void beforeUpdate() {
        RES_LeadServices.setUpdateSLATimeOnLead((list<lead>)Trigger.new, (Map<id, lead>)Trigger.oldMap,false, null);
    }
    
}