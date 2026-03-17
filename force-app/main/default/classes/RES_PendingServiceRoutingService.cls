public with sharing class RES_PendingServiceRoutingService {
    public RES_PendingServiceRoutingService() {
    }


    public static void startSLA(List<PendingServiceRouting> pendingServiceRoutingList){
        List<Lead> leadList = new List<Lead>();
        Set<Id> leadIds = new Set<Id>();
        Map<Id, Id> prevOwnerMapping = new Map<Id, Id>();

        for(PendingServiceRouting psr: pendingServiceRoutingList){
            if(psr.WorkItemId != null && String.valueOf(psr.workItemId).startsWith('00Q')){
                leadIds.add(psr.workItemId);
                if(psr.GroupId!= null && String.valueOf(psr.GroupId).startsWith('00G')){
                    prevOwnerMapping.put(psr.workItemId, psr.GroupId);
                }
            }
        }
        
        leadList = new RES_LeadDAOLayer().getLeadsById(leadIds);

        if(leadList.isEmpty()){
            return;
        }
        
        System.debug('PSR'+ leadList);
        RES_LeadServices.setUpdateSLATimeOnLead(leadList, null , true, prevOwnerMapping);
    }
}