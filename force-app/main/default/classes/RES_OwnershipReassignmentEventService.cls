/**
 * @ class name         : RES_OwnershipReassignmentEventService
 * @ description        : This class is designed to handle the Ownership Reassignment Logic.
 * @ author             : Saurabh Mulay
 */

public with sharing class RES_OwnershipReassignmentEventService {
    public RES_OwnershipReassignmentEventService() {}

    public static void processOwnershipReassignment(List<RES_Ownership_Reassignment_Event__e> events) {
        List<Lead> leadToUpdate = new List<Lead>();

        for (RES_Ownership_Reassignment_Event__e event : events) {
            if(event.RES_LeadId__c != null && event.RES_OwnerId__c != null){
                Lead l = new Lead(
                        Id  = event.RES_LeadId__c,
                        OwnerId = event.RES_OwnerId__c,
                        RES_Bypass_Assignment_Rules__c = true
                    );

                if(String.valueOf(l.ownerId).startsWith('00G')){
                    l.RES_SLA_Start_Time__c = null;
                    l.RES_SLA_Due_Time__c = null;
                    l.RES_SLA_Status__c = null;
                }

                leadToUpdate.add(l);
            }
        }
        
        Database.update(leadToUpdate, true, AccessLevel.SYSTEM_MODE);
    }

}

