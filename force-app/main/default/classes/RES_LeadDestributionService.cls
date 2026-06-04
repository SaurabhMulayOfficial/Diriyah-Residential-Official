public with sharing class RES_LeadDestributionService {
    public RES_LeadDestributionService() {}
    public static List<RES_ReassignmentLogicHandler.leadRoutingWrapper> routingUpdates = new List<RES_ReassignmentLogicHandler.leadRoutingWrapper>();

    public static void handleLeadReassignment(List<RES_Lead_Distribution__e> leadDistributionList){
        Set<String> queueNames = new Set<String>();

        for(RES_Lead_Distribution__e event: leadDistributionList){
            queueNames.add(event.RES_Queue__c);
        }

        System.debug('Queues '+ queueNames);

        Map<String,Id> queueNametoIdMapping= new RES_GroupDAOLayer().getQueueMappingbyIds(queueNames);
        Set<Id> ownerIds = new Set<Id>(queueNametoIdMapping.values());
        List<Lead> leadList = new RES_LeadDAOLayer().getLeadByOwnerIds(ownerIds);
        System.debug('leadList'+ leadList);

        if(leadList.isEmpty())return;

        RES_ReassignmentLogicHandler.runLeadReassignment(leadList, routingUpdates);

        try{
            Database.update(leadList, false, AccessLevel.SYSTEM_MODE);
            RES_ReassignmentLogicHandler.updateRoutingRecords(routingUpdates);
        }catch(Exception e){
            System.debug('Failed to Update Leads OR Failed to create Lead-Routing Records ' + e.getMessage());
        }
        
    }
}