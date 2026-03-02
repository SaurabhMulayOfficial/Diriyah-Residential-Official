/**
 * Service class for Lead business logic
 * Called from RES_LeadTriggerHandler
 */
public with sharing class RES_LeadServices {

    public static void setUpdateSLATimeOnLead(List<Lead> leadList, Map<id, Lead> oldMap){
        if(leadList == null || leadList.isEmpty()){
            return;
        }

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
                if(l.status == '01' && String.valueOf(l.ownerId).startsWith('005')){
                    startSla(L, bh, slaInHours);
                }
            }
        }
        else{
            for(Lead l: leadList){
                if(l.Status != oldMap.get(l.Id).Status && l.OwnerId == Userinfo.getUserId()){
                    if(l.RES_SLA_Status__c == 'Running' && SYSTEM.now() < l.RES_SLA_Due_Time__c){
                        l.RES_SLA_Status__c = 'Met';
                        l.RES_SLA_Due_Time__c = null;
                    }    
                }
                else if(l.RES_SLA_Status__c != oldMap.get(l.Id).RES_SLA_Status__c && l.RES_SLA_Status__c == 'Breached'){
                    String userIdToAssign = '';
                    if(groupToUserMapping.containsKey(l.RES_Previous_Lead_Owner__c)){
                        Set<Id> users = groupToUserMapping.get(l.RES_Previous_Lead_Owner__c);
                        for(Id u: users){
                            if(activeUsers.contains(u) && u != l.OwnerId){
                                userIdToAssign = u;
                                break;
                            }else if(u != l.OwnerId){
                                userIdToAssign = u;
                            }
                        }
                    }
                    
                    if(!String.isBlank(userIdToAssign)){
                        l.OwnerId = userIdToAssign;
                        startSla(L, bh, slaInHours);
                    }
                }
                else if(l.OwnerId != oldmap.get(l.Id).OwnerId && String.valueOf(l.ownerId).startsWith('005') && String.valueOf(oldmap.get(l.Id).OwnerId).startsWith('00G')){
                    if(l.RES_SLA_Status__c != 'Met'){
                        startSla(L, bh, slaInHours);
                    }
                    
                }
            }

        }
    
    }

    private static void startSla(Lead L, BusinessHours bh, Integer slaInHours){
        l.RES_SLA_Cycle_Count__c += 1;
        l.RES_SLA_Start_Time__c = SYSTEM.now();
        l.RES_SLA_Status__c = 'Running';
        l.RES_SLA_Due_Time__c = BusinessHours.add(bh.Id,SYSTEM.now(), slaInHours * 60 * 60 * 1000);
    }

}