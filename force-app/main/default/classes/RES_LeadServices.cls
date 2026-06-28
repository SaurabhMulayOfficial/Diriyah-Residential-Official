/**
 * Service class for Lead business logic
 * Called from RES_LeadTriggerHandler
 */
public with sharing class RES_LeadServices {
    public static Set<Lead> avoidReassignment = new Set<Lead>();

    public static List<RES_LeadDeduplicationHandler.LeadDuplicateWrapper> leadDuplicateWrapper = 
    new List<RES_LeadDeduplicationHandler.LeadDuplicateWrapper>();
    public static Map<Id, Database.LeadConvertResult> conversionResults = new Map<Id, Database.LeadConvertResult>();

    public static List<RES_ReassignmentLogicHandler.leadRoutingWrapper> routingUpdates = new List<RES_ReassignmentLogicHandler.leadRoutingWrapper>();
    
    public class InputWrapper {
        @InvocableVariable(required=true)
        public Id leadId;
        @InvocableVariable(required=true)
        public Id currentOwnerId;
    }
    
    @InvocableMethod(label='Handle Lead Owner Change')
    public static void getNewOwnerForRetiredLeads(List<InputWrapper> inputs){
        Integer slaInHours = Integer.valueOf(SYSTEM.Label.RES_Lead_SLA_In_hours);
        BusinessHours bh = (BusinessHours) new RES_BusinessHoursDAOLayer().getDefaultBusinessHours()[0];
        Set<Id> leadIds = new Set<Id>();
    
        for(InputWrapper input: inputs){
            leadIds.add(input.leadId);
        }

        List<Lead> queriedLeads = new RES_LeadDAOLayer().getLeadsById(leadIds);
        if(!queriedLeads.isEmpty()){

            RES_ReassignmentLogicHandler.runLeadReassignment(queriedLeads, routingUpdates);
            RES_LeadServices.updateRoutingRecordResults();
            
            for(Lead l: queriedLeads){
                if(!String.valueOf(l.OwnerId).startsWith('005'))continue; 

                startSla(l, bh, slaInHours, true);
                l.RES_SLA_Cycle_Count__c = 0;
                l.RES_SLA_Breach_Time__c = null;
                l.status = '01';
                l.RES_Lead_Sub_Status__c =  null;
            }
            
            try{
                Database.update(queriedLeads, true, AccessLevel.SYSTEM_MODE);
                clearStaticVariables();    
            }
            catch(Exception e){
                System.debug('LeadServices.getNewOwnerForRetiredLeads: Failed to change Owner of Lead '+ e.getMessage());
            } 

        }
    }

    public static void publishReassignmentEventInBulk(List<RES_Ownership_Reassignment_Event__e> events){
        try{
            List<Database.SaveResult> results  = EventBus.publish(events);
            System.debug('Events published for lead ownership reassignment with results: ' + results);

        }catch(Exception e){
            System.debug('Failed to publish event for lead ownership reassignment: ' + e.getMessage());
        }
    }

    public static void setUpdateSLATimeOnLead(List<Lead> leadList, Map<id, Lead> oldMap, Boolean psr, Map<Id,Id> previousOwner){
        if(leadList == null || leadList.isEmpty()){
            return;
        }
    
        Integer slaInHours = Integer.valueOf(SYSTEM.Label.RES_Lead_SLA_In_hours);
        BusinessHours bh = (BusinessHours) new RES_BusinessHoursDAOLayer().getDefaultBusinessHours()[0];
        Set<Id> queueIds = new Set<Id>();
        set<Id> activeUsers = new Set<Id>();

        List<Lead> leadForReassignment = new List<Lead>();


        if(oldmap != null){
            for(lead l: leadList){
                if(!String.isBlank(l.RES_Previous_Lead_Owner__c)){
                    queueIds.add(l.RES_Previous_Lead_Owner__c);
                }
            }
        }
        
        if(oldMap == null){
            for(Lead l: leadList){
                if(l.LeadSource == 'Z09'){
                    continue;
                }
                if(l.status == '01' && (l.OwnerId != null && String.valueOf(l.ownerId).startsWith('005'))){
                    startSla(l, bh, slaInHours, false);
                }
            }
        }
        else{
            for(Lead l: leadList){
                if(l.LeadSource == 'Z09'){
                    continue;
                }
                if(l.Status != oldMap.get(l.Id).Status){
                    if(l.RES_SLA_Status__c == 'Running' && SYSTEM.now() < l.RES_SLA_Due_Time__c && l.Status != '01'){
                        l.RES_SLA_Status__c = 'Met';
                        l.RES_SLA_Due_Time__c = null;
                    }    
                }
                else if(l.RES_SLA_Status__c != oldMap.get(l.Id).RES_SLA_Status__c && l.RES_SLA_Status__c == 'Breached'){
                    startSla(l, bh, slaInHours, true);
                    leadForReassignment.add(l);
                }
                else if((oldmap.get(l.Id).OwnerId == null && String.valueOf(l.ownerId).startsWith('005')) || (l.OwnerId != oldmap.get(l.Id).OwnerId && String.valueOf(l.ownerId).startsWith('005'))){
                    if(l.RES_SLA_Status__c != 'Met' && l.status == '01'){
                        startSla(l, bh, slaInHours, false);
                    }
                }
            }
        }

        if(!leadForReassignment.isEmpty()){
            RES_ReassignmentLogicHandler.runLeadReassignment(leadForReassignment, routingUpdates);
            RES_LeadServices.updateRoutingRecordResults();
            clearStaticVariables();    

            try{
                Database.update(leadForReassignment, true, AccessLevel.SYSTEM_MODE);
            }catch(Exception e){
                System.debug('Failed to update SLA fields on Lead after reassignment: ' + e.getMessage());
            }
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


    public static void selectLeadRecordType(List<Lead> newLeadList){
        Id individualRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
                                    .get('RES_Individual').getRecordTypeId();
        Id companyRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
                                    .get('RES_Company').getRecordTypeId();

        for (Lead l : newLeadList) {
            if(l.LeadSource == 'Z06' && l.RES_Form_Submission_ID__c != null){
                if(l.RES_Marketing_Area__c == 'BRANDED_RESIDENTIAL' || l.RES_Marketing_Area__c == 'WADI_SAFAR'){
                    l.RecordTypeId = individualRecordTypeId;
                } else {
                    l.RecordTypeId = companyRecordTypeId;
                }
            }
        }
    }

    public static void runReassignmentRule(List<Lead> leadList){
        RES_ReassignmentLogicHandler.runLeadReassignment(leadList, routingUpdates);
    }

    public static void applyDeduplicationRules(List<Lead> leadList){
        RES_LeadDeduplicationHandler.apply(leadList,leadDuplicateWrapper);
    }

    public static void processDeduplicationResults(){
        RES_LeadDeduplicationHandler.processResults(leadDuplicateWrapper);
    }

    public static void updateRoutingRecordResults(){
        if(routingUpdates.isEmpty()){
            System.debug('No routing updates to process');
            return;
        }
        RES_ReassignmentLogicHandler.updateRoutingRecords(routingUpdates);
    }


    public static void manageLeadRoutingRecords(List<Lead> leadList, Map<Id, Lead> oldMap){
        if(leadList == null || leadList.isEmpty()){
            return;
        }

        Set<Id> ownerIds = new Set<Id>();
        Set<Id> leadIds = new Set<Id>();

        for(Lead l: leadList){
            if(l.OwnerId != oldMap.get(l.Id).OwnerId){
                leadIds.add(l.Id);
                ownerIds.add(l.ownerId);
            }
        }

        List<RES_Lead_Routing__c> leadRoutingRecords = new RES_LeadRoutingDAO().getRoutingRecordsByLeadIds(leadIds);

        try{
            deleteRoutingRecords(leadRoutingRecords);
        }catch(Exception e){
            System.debug('Failed to manage lead routing records: ' + e.getMessage());
        }

        List<RES_Assignment_Workload__c> workloadRecords = new RES_AssignmentWorkloadDAO().getWorkloadByUserIds(ownerIds);
        List<RES_Lead_Routing__c> routingRecordsToInsert = new List<RES_Lead_Routing__c>();

        Map<Id, Id> userToWorkloadMapping = new Map<Id, Id>();
        for(RES_Assignment_Workload__c workload:workloadRecords){
            userToWorkloadMapping.put(workload.RES_User__c, workload.Id);
        }

        for(Lead l: leadList){
            if(l.OwnerId != oldMap.get(l.Id).OwnerId){
                if(userToWorkloadMapping.containsKey(l.ownerId)){
                    Id workId = userToWorkloadMapping.get(l.ownerId);
                    routingRecordsToInsert.add(new RES_Lead_Routing__c(RES_Assignment_Workload__c = workId,  RES_Lead__c = l.Id));
                }
            }
        }

        try {
            RES_ReassignmentLogicHandler.createRoutingRecords(routingRecordsToInsert);
        } catch (Exception e) {
            System.debug('Failed to create lead routing records: ' + e.getMessage());
        }
    }

    public static void deleteRoutingRecords(List<RES_Lead_Routing__c> leadRoutingRecords){
        try{
            Database.delete(leadRoutingRecords, true, AccessLevel.SYSTEM_MODE);
        }catch(Exception e){
            System.debug('Failed to delete lead routing records: ' + e.getMessage());
        }
    }
    public static void clearStaticVariables(){
        leadDuplicateWrapper.clear();
        routingUpdates.clear();
    }

    /**
 * @description Converts qualified leads synchronously in beforeUpdate
 *              Stores results for publishing in afterUpdate
 */
public static void convertQualifiedLeads(List<Lead> leads, Map<Id, Lead> oldMap){
    Id rtIdCompany = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('RES_Company').getRecordTypeId();
    Id rtIdIndividual = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('RES_Individual').getRecordTypeId();
    
    List<Lead> qualifiedLeads = new List<Lead>();
    for(Lead l : leads){
        if(l.RecordTypeId != rtIdCompany && l.RecordTypeId != rtIdIndividual){
            continue;
        }
        if(l.Status == '04' && oldMap.get(l.Id).Status != '04'){
            qualifiedLeads.add(l);  
        }
    }
    if(qualifiedLeads.isEmpty()){
        return;
    }
    try {
        if(Limits.getQueueableJobs() == 0) {
            System.enqueueJob(new RES_LeadConversionQueueable(qualifiedLeads));
        }
    } catch(Exception ex) {
        System.debug(LoggingLevel.ERROR, 'Failed to enqueue: ' + ex.getMessage());
    }

    public static void clearStaticVariables(){
        leadDuplicateWrapper.clear();
        routingUpdates.clear();
}
}