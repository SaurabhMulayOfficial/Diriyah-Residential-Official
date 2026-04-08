/**
 * Service class for Lead business logic
 * Called from RES_LeadTriggerHandler
 */
public with sharing class RES_LeadServices {

    public class InputWrapper {
        @InvocableVariable(required=true)
        public Id leadId;

        @InvocableVariable(required=true)
        public Id previousOwnerId;

        @InvocableVariable(required=true)
        public Id currentOwnerId;
    }
    
    @InvocableMethod(label='Handle Lead Owner Change')
    public static void getNewOwnerForRetiredLeads(List<InputWrapper> inputs){
        List<Lead> leadsToUpdate = new List<Lead>();

        Set<Id> queueIds = new Set<Id>();
        Set<Id> activeUsers = new Set<Id>();

        for(InputWrapper input: inputs){
            if(input.leadId != null && input.previousOwnerId != null){
                queueIds.add(input.previousOwnerId);
            }
        }

        if(queueIds.isEmpty())return;

        List<UserServicePresence> userPresence = new RES_UserServicePresenceDAOLayer().getActiveUsers();
        
        if(!userPresence.isEmpty()){
            for(UserServicePresence u: userPresence){
                activeUsers.add(u.userId);
            }
        }

        Map<Id, Set<Id>> groupToUserMapping = new Map<Id,Set<Id>>();

        if(!queueIds.isEmpty()){
            groupToUserMapping = new RES_GroupMemberDAOLayer().getGroupMembersByIds(queueIds);
        }

        for(InputWrapper input: inputs){
            if(input.leadId == null)continue;
            if(!String.valueOf(input.currentOwnerId).startsWith('005'))continue; 
            Id nextOwner = getNextOwner(input.previousOwnerId, input.currentOwnerId, groupToUserMapping, activeUsers);
            if(nextOwner != null){
                Lead l = new Lead();
                l.Id = input.leadId;
                l.OwnerId = nextOwner;
                leadsToUpdate.add(l);
            }
        }

        if(leadsToUpdate.isEmpty()){
            return;
        }
        
        try{
            Database.upsert(leadsToUpdate, true, AccessLevel.SYSTEM_MODE);
        }
        catch(Exception e){
            System.debug('LeadServices.getNewOwnerForRetiredLeads: Failed to change Owner of Lead '+ e.getMessage());
        }
    }

    public static void setUpdateSLATimeOnLead(List<Lead> leadList, Map<id, Lead> oldMap, Boolean psr, Map<Id,Id> previousOwner){
        if(leadList == null || leadList.isEmpty()){
            return;
        }
        List<Lead> toUpdate = new List<lead>();

        Integer slaInHours = Integer.valueOf(SYSTEM.Label.RES_Lead_SLA_In_hours);
        BusinessHours bh = (BusinessHours) new RES_BusinessHoursDAOLayer().getDefaultBusinessHours()[0];
        Set<Id> queueIds = new Set<Id>();
        set<Id> activeUsers = new Set<Id>();

        if(oldmap != null){
            for(lead l: leadList){
                if(!String.isBlank(l.RES_Previous_Lead_Owner__c)){
                    queueIds.add(l.RES_Previous_Lead_Owner__c);
                }
            }

            List<UserServicePresence> userPresence = new RES_UserServicePresenceDAOLayer().getActiveUsers();

            for(UserServicePresence u: userPresence){
                activeUsers.add(u.UserId);
            }
        }

        Map<Id, Set<Id>> groupToUserMapping = new Map<Id,Set<Id>>();

        if(!queueIds.isEmpty()){
            groupToUserMapping = new RES_GroupMemberDAOLayer().getGroupMembersByIds(queueIds);
        }
        
        if(oldMap == null){
            for(Lead l: leadList){
                if(l.LeadSource == 'Z09'){
                    continue;
                }
                if(l.status == '01' && (l.OwnerId != null && String.valueOf(l.ownerId).startsWith('005'))){
                    startSla(l, bh, slaInHours, false);
                    if(psr == true){
                        if(previousOwner != null && previousOwner.containsKey(l.Id)){
                            l.RES_Previous_Lead_Owner__c = previousOwner.get(l.Id);
                        }
                        toUpdate.add(l);
                    }
                }
            }
        }
        else{
            for(Lead l: leadList){
                if(l.LeadSource == 'Z09'){
                    continue;
                }
                if(l.Status != oldMap.get(l.Id).Status && l.OwnerId == Userinfo.getUserId()){
                    if(l.RES_SLA_Status__c == 'Running' && SYSTEM.now() < l.RES_SLA_Due_Time__c){
                        l.RES_SLA_Status__c = 'Met';
                        l.RES_SLA_Due_Time__c = null;
                    }    
                }
                else if(l.RES_SLA_Status__c != oldMap.get(l.Id).RES_SLA_Status__c && l.RES_SLA_Status__c == 'Breached'){
                    Id userIdToAssign;
                    if(groupToUserMapping.containsKey(l.RES_Previous_Lead_Owner__c)){
                        userIdToAssign = getNextOwner(l.RES_Previous_Lead_Owner__c, l.OwnerId, groupToUserMapping, activeUsers);
                    }
                    
                    if(userIdToAssign != null){
                        l.OwnerId = userIdToAssign;
                        startSla(l, bh, slaInHours, true);
                    }
                }
                else if((oldmap.get(l.Id).OwnerId == null && String.valueOf(l.ownerId).startsWith('005')) || (l.OwnerId != oldmap.get(l.Id).OwnerId && String.valueOf(l.ownerId).startsWith('005') && String.valueOf(oldmap.get(l.Id).OwnerId).startsWith('00G'))){
                    if(l.RES_SLA_Status__c != 'Met'){
                        startSla(l, bh, slaInHours, false);
                    }
                    
                }
            }

        }

        if(psr == true && !toUpdate.isEmpty()){
            Database.upsert(toUpdate, true, AccessLevel.SYSTEM_MODE);
        }
    
    }

    private static void startSla(Lead l, BusinessHours bh, Integer slaInHours, Boolean shouldCycleCount){
        if(l.RES_SLA_Cycle_Count__c == null)l.RES_SLA_Cycle_Count__c=0;
        if(shouldCycleCount == true){
            l.RES_SLA_Cycle_Count__c += 1;
        }
        l.RES_SLA_Start_Time__c = SYSTEM.now();
        l.RES_SLA_Status__c = 'Running';
        l.RES_SLA_Due_Time__c = BusinessHours.add(bh.Id,SYSTEM.now(), slaInHours * 60 * 60 * 1000);
    }

    public static Id getNextOwner(
        Id previousQueueId,
        Id currentOwnerId,
        Map<Id, Set<Id>> groupToUserMapping,
        Set<Id> activeUsers
    ) {
        if(previousQueueId == null || !groupToUserMapping.containsKey(previousQueueId)){
            return null;
        }

        Set<Id> users = groupToUserMapping.get(previousQueueId);
        Id fallbackUser;

        for(Id u : users){
            if(u == currentOwnerId) continue;
            if(activeUsers.contains(u)){
                return u;
            }
        }

        if(users.contains(currentOwnerId)){
            users.remove(currentOwnerId);
        }

        list<Id> userList = new List<Id>(users);
        Integer N = userList.size();
        if(N <= 0) return fallbackUser;
        Integer randomIndex = (Integer) Math.mod(Math.abs(Crypto.getRandomInteger()), N);
        fallbackUser = userList[randomIndex];
        return fallbackUser;
    }

    public static void selectLeadRecordType(List<Lead> newLeadList){
        Id individualRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
                                    .get('RES_Individual').getRecordTypeId();
        Id companyRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
                                    .get('RES_Company').getRecordTypeId();

        for (Lead l : newLeadList) {
            if (l.RES_Marketing_Area__c == 'BRANDED_RESIDENTIAL' || l.RecordTypeId == individualRecordTypeId) {
                l.RecordTypeId = individualRecordTypeId;
            } else {
                l.RecordTypeId = companyRecordTypeId;
            }
        }
    }

    public static void applyDeduplicationRules(List<Lead> leadList){
        RES_LeadDeduplicationHandler.apply(leadList);
    }

}