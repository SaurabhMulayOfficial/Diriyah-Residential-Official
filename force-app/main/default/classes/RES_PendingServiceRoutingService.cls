public with sharing class RES_PendingServiceRoutingService {

    public class FlowInput {
        @InvocableVariable(required=true)
        public Id workItemId;

        @InvocableVariable
        public Id groupId;
    }


    @InvocableMethod(label='Start SLA from Flow')
    public static void startSLAFromFlow(List<FlowInput> inputs) {
        Set<Id> leadIds = new Set<Id>();
        Map<Id, Id> prevOwnerMapping = new Map<Id, Id>();

        for(FlowInput input : inputs){
            if(input.workItemId != null && !String.valueOf(input.workItemId).startsWith('00Q'))continue;
            if(input.groupId != null && String.valueOf(input.groupId).startsWith('00G')){
                prevOwnerMapping.put(input.workItemId, input.groupId);
            }
            leadIds.add(input.workItemId);
        }

        if(leadIds.size() <= 0){
            return;
        }

        List<lead> leadList = new RES_LeadDAOLayer().getLeadsById(leadIds);
        RES_LeadServices.setUpdateSLATimeOnLead(leadList, null , true, prevOwnerMapping);
    }
    
}