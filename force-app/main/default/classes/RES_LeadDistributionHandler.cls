public with sharing class RES_LeadDistributionHandler extends RES_BaseTriggerHandler{
    public RES_LeadDistributionHandler() {}

    protected override void afterInsert(){
        RES_LeadDestributionService.handleLeadReassignment((List<RES_Lead_Distribution__e>) Trigger.new);
    }
}