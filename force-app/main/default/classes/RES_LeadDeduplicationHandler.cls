/**
 * @ class name         : RES_LeadDeduplicationHandler
 * @ description        : This class is designed to handle the Lead Deduplication Logic.
 * @ author             : Saurabh Mulay
 */

public without sharing class RES_LeadDeduplicationHandler {

    public class Notify{
        public String recipientQueue;
        public Lead leadInstance; 
    }

    public static List<Notify> notifyOperationTeam = new List<Notify>();
    public static List<Notify> notifyCSO = new List<Notify>();
    public static Id orgWideEmailAddressId;
    

    public class LeadDuplicateWrapper {
        public Lead inputLead;
        public List<Lead> duplicateLeads = new List<Lead>();
        public Boolean hasDuplicates = false;
        public Boolean hasError = false;
        public List<String> errors = new List<String>();
        public Set<Id> duplicateLeadIds = new Set<Id>();
        public Map<String,List<Lead>> leadBySource = new Map<String,List<Lead>>();

        public Boolean isOwnerChange = false;
        public String newOwnerId = '';

        public LeadDuplicateWrapper(Lead inputLead) {
            this.inputLead = inputLead;
        }   
    }

    public static Map<String, Id> queueMapping = new Map<String, Id>();

    public static void apply(List<lead> leadList){
        if(leadList.isEmpty())return;
        List<LeadDuplicateWrapper> duplicateLeadsWrapper = getDuplicateLeads(leadList);
        duplicateLeadsWrapper = hydrateDuplicateWrapper(duplicateLeadsWrapper);

        Set<String> queueNames = new Set<String>();
        for (String queueName : System.Label.RES_Notify_Queues_for_Duplication.split(',')) {
            queueNames.add(queueName.trim());
        }

        queueMapping = new RES_GroupDAOLayer().getQueueMappingbyIds(queueNames);

        List<OrgWideEmailAddress> orgWideAddress= new RES_OrgWideAddressDAO().getOrgWideAddressByDisplayName(
            'Salesforce Notifications'
        );

        if(orgWideAddress.size() > 0){
            orgWideEmailAddressId = orgWideAddress[0].Id;
        }

        System.debug(' Hydrated Duplicate Lead Wrapper ' + duplicateLeadsWrapper + 'Queue Names are ' + queueMapping);
        runRuleEngine(duplicateLeadsWrapper);
    }

    public static List<LeadDuplicateWrapper> getDuplicateLeads(List<Lead> inputLeads) {

        List<LeadDuplicateWrapper> response = new List<LeadDuplicateWrapper>();

        if (inputLeads == null || inputLeads.isEmpty()) {
            return response;
        }
        Id rtId_company = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('RES_Company').getRecordTypeId();
        Id rtId_individual = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('RES_Individual').getRecordTypeId();
        
        for (Lead l : inputLeads) {
            if(l.RecordTypeId != rtId_company && l.RecordTypeId != rtId_individual){
                continue;
            }
            response.add(new LeadDuplicateWrapper(l));
        }

        List<Datacloud.FindDuplicatesResult> results = Datacloud.FindDuplicates.findDuplicates(inputLeads);

        for (Integer i = 0; i < results.size(); i++) {

            LeadDuplicateWrapper wrapper = response[i];
            Datacloud.FindDuplicatesResult result = results[i];

            if (!result.isSuccess()) {
                wrapper.hasError = true;
                for (Database.Error err : result.getErrors()) {
                    wrapper.errors.add(err.getMessage());
                }
                continue;
            }

            for (Datacloud.DuplicateResult dupResult : result.getDuplicateResults()) {

                for (Datacloud.MatchResult matchResult : dupResult.getMatchResults()) {

                    if (!matchResult.isSuccess()) {
                        wrapper.hasError = true;
                        for (Database.Error err : matchResult.getErrors()) {
                            wrapper.errors.add(err.getMessage());
                        }
                        continue;
                    }

                    for (Datacloud.MatchRecord matchRecord : matchResult.getMatchRecords()) {
                        SObject record = matchRecord.getRecord();

                        if(record.getSObjectType() == Lead.SObjectType) {
                            Lead dupLead = (Lead) record;
                            wrapper.duplicateLeadIds.add(dupLead.Id);

                        }
                    }
                }
            }

            if (!wrapper.duplicateLeadIds.isEmpty()) {
                wrapper.hasDuplicates = true;
            }
        }

        return response;
    }

    public static list<LeadDuplicateWrapper> hydrateDuplicateWrapper(list<LeadDuplicateWrapper> response){

        if(response.size() <= 0)return response;

        Set<Id> allCollectedLeadIds = new Set<Id>();

        for(LeadDuplicateWrapper wrapper: response){
            if(wrapper.duplicateLeadIds.isEmpty()){
                continue;
            }
            allCollectedLeadIds.addAll(wrapper.duplicateLeadIds);
        }

        Map<Id, Lead> duplicateLeadMapping = new RES_LeadDAOLayer().getLeadByIds(allCollectedLeadIds, true);
        
        for(LeadDuplicateWrapper wrapper: response){
            if(wrapper.duplicateLeadIds.isEmpty())continue;

            for(Id leadId: wrapper.duplicateLeadIds){
                if(duplicateLeadMapping.containsKey(leadId)){
                    Lead l = duplicateLeadMapping.get(leadId);
                    wrapper.duplicateLeads.add(l);
                    
                    if(l.LeadSource != null){
                        if(!wrapper.leadBySource.containsKey(l.LeadSource)){
                            wrapper.leadBySource.put(l.LeadSource, new List<Lead>());
                        }

                        wrapper.leadBySource.get(l.LeadSource).add(l);
                    }
                }
            }
        }

        return response;
    }

    public static String getRmId(List<Lead> existingLeadsByExistingSource){
        String userId = '';

        for(Lead existingLead : existingLeadsByExistingSource){
            if(String.valueOf(existingLead.OwnerId).startsWith('005')){
                userId = String.valueOf(existingLead.OwnerId);
                return userId;
            }
        }

        return userId;
    }

    public static boolean isOnlyBlockRule(Lead_Deduplication_Rule__mdt rule){
        return rule.Action__c != null &&
            rule.Action__c.toUpperCase() == 'BLOCK' && 
            String.isBlank(rule.Assigned_To__c) &&
            String.isBlank(rule.Block_Notification_Queue__c) &&
            String.isBlank(rule.Allow_Creation_Notify_Queue__c) &&
            String.isBlank(rule.Lead_Status__c);
    }

    public static boolean isBlockAndNotifyRule(Lead_Deduplication_Rule__mdt rule){
        return (String.isNotBlank(rule.Block_Notification_Queue__c) && 
                String.isNotBlank(rule.Allow_Creation_Notify_Queue__c) &&
                String.isNotBlank(rule.Action__c) && String.isBlank(rule.Assigned_To__c) &&
                String.isBlank(rule.Lead_Status__c));
    }

    public static Boolean isNoBlockSameRMRule(Lead_Deduplication_Rule__mdt rule){
        return (String.isBlank(rule.Block_Notification_Queue__c) && 
                String.isBlank(rule.Allow_Creation_Notify_Queue__c) &&
                String.isNotBlank(rule.Action__c) && String.isNotBlank(rule.Assigned_To__c) &&
                String.isNotBlank(rule.Lead_Status__c));
    }

    public static Map<String, String> getLeadSourceMap() {
        Map<String, String> leadSourceMap = new Map<String, String>();
        for (Schema.PicklistEntry entry : Lead.LeadSource.getDescribe().getPicklistValues()) {
            leadSourceMap.put(entry.getValue(), entry.getLabel());
        }
        return leadSourceMap;
    }

    public static void publishReassignmentEvent(String leadId, String ownerId){
        RES_Ownership_Reassignment_Event__e event = new RES_Ownership_Reassignment_Event__e();
        event.RES_LeadId__c = leadId;
        event.RES_OwnerId__c = ownerId;
        Database.SaveResult result = EventBus.publish(event);

        if (result.isSuccess()) {
            System.debug('Event published successfully' + ' ' + leadId + '  ' + ownerId);   
        } else {
            System.debug('Failed to publish event' + leadId + '  ' + ownerId);
        }
    }

    public static void runRuleEngine(List<LeadDuplicateWrapper> input){
        List<Lead_Deduplication_Rule__mdt> rules = new RES_LeadDeduplicationDAOLayer().getAllRules();

        Map<String, String> leadSourceMap = getLeadSourceMap();

        for(LeadDuplicateWrapper wrapper : input){
            if(wrapper.hasDuplicates == false)continue;

            if(wrapper.hasError == true){
                System.debug('Errors in Duplicates '+ wrapper.errors);
                continue;
            }

            Lead inputLead = wrapper.inputLead;
            Map<String, List<Lead>> leadBySource = wrapper.leadBySource;
            
            for(Lead_Deduplication_Rule__mdt rule: rules){
                if(rule.Source__c == null)continue;
                
                List<String> source = rule.Source__c.split('-');
                
                if(source.size() <= 1)continue;

                String incomingSource = source[0];
                String existingSource = source[1];

                if(inputLead.LeadSource != incomingSource)continue;

                String assignedTo = rule.Assigned_To__c != null ? rule.Assigned_To__c.toUpperCase() : '';
                String action = rule.Action__c != null ? rule.Action__c.toUpperCase() : '';

                if(leadBySource != null && leadBySource.containsKey(existingSource)){
                    List<Lead> existingLeadsByExistingSource = leadBySource.get(existingSource);
                    
                    List<Lead> retiredAndArchiveLeads = new List<Lead>();
                    List<Lead> newAndActiveLeads = new List<Lead>();

                    for(Lead iterator: existingLeadsByExistingSource){
                        if(iterator.status == '05' || iterator.Status == 'Archive'){
                            retiredAndArchiveLeads.add(iterator);
                        }
                        else if(iterator.Status == '01' || iterator.Status == '02'){
                            newAndActiveLeads.add(iterator);
                        }
                    }

                    if(retiredAndArchiveLeads.size() <= 0 && newAndActiveLeads.size() <= 0){
                        break;
                    }
                    
                    String shouldArchive = rule.Lead_Status__c;

                    String displayIncomingSource = leadSourceMap.containsKey(incomingSource) ? leadSourceMap.get(incomingSource) : incomingSource;
                    String displayExistingSource = leadSourceMap.containsKey(existingSource) ? leadSourceMap.get(existingSource) : existingSource;
                    
                    //Anyway Block
                    if(isOnlyBlockRule(rule)){
                        System.debug('Simply Blocking by rule');
                        inputLead.addError('Please review duplicates, The incoming Lead has '+ displayIncomingSource +' as Source and the existing duplicate Lead has ' + displayExistingSource + ' as a Source.');
                        break;
                    }

                    //Block + Notify to Operation Team or Assign to Residential Duplicate Queue.
                    if(isBlockAndNotifyRule(rule)){
                        //check if existing lead is active/New
                        if(incomingSource == 'Z09' && existingSource == 'Z09'){
                            Id existingRM = getRmId(existingLeadsByExistingSource);
                            if(existingRM != null && inputLead.OwnerId == existingRM){
                                inputLead.addError('Please review duplicates, The incoming Lead has '+ displayIncomingSource +' as Source and the existing duplicate Lead has ' + displayExistingSource + ' as a Source.');
                                break;
                            }
                        }

                        if(newAndActiveLeads.size() > 0){
                            if(orgWideEmailAddressId != null){
                                RES_Send_Email__e event = new RES_Send_Email__e();
                                event.Merge_Fields__c = inputLead.FirstName + ' ' + inputLead.LastName + ',' + inputLead.MobilePhone + ',' + inputLead.Email;
                                event.Group__c = rule.Block_Notification_Queue__c;
                                event.Type__c = 'Lead Duplication';
                                event.OrgWideAddressID__c = orgWideEmailAddressId;
                                try{
                                    EventBus.publish(event);
                                }catch(Exception e){
                                    System.debug('Error Publishing Send Email Platform Event ' + e.getMessage());
                                }
                            }

                            inputLead.addError(SYSTEM.Label.RES_Duplicate_Lead_Block_Notification);
                            break;
                        }
                        //else check if retired / Archived.
                        else if(retiredAndArchiveLeads.size() > 0){
                            Notify emailNode = new Notify();
                            emailNode.leadInstance = inputLead;
                            emailNode.recipientQueue = rule.Allow_Creation_Notify_Queue__c;
                            notifyCSO.add(emailNode);
                            Id fallbackQueueId;
                            if(queueMapping.containsKey(rule.Allow_Creation_Notify_Queue__c)){
                                fallbackQueueId = queueMapping.get(rule.Allow_Creation_Notify_Queue__c);
                            }
                            inputLead.OwnerId = fallbackQueueId;
                            RES_LeadServices.avoidReassignment.add(inputLead);
                            break;
                        }
                    }

                    // Assignment to Same RM + Mark Lead Archive
                    if(isNoBlockSameRMRule(rule)){
                        String getSameRMId = getRmId(existingLeadsByExistingSource);
                        inputLead.status = rule.Lead_Status__c;

                        if(assignedTo == 'SAME'){
                            if(getSameRMId != ''){
                                inputLead.OwnerId = getSameRMId;
                                RES_LeadServices.avoidReassignment.add(inputLead);
                                break;
                            }
                        }
                    }
                }
            }
        }
    }


    public static void processEmails(){
        System.debug('Processing Email Results CSO ' + notifyCSO.size());
    
        if(orgWideEmailAddressId == null){
            System.debug('Org Wide Email Not Found Named "Salesforce Notifications');
            return;
        }
        Set<String> groupNames = new Set<String>();

        for(Notify node: notifyCSO){
            groupNames.add(node.recipientQueue);
        }

        Map<String, Set<String>> groupToEmailsMapping = new RES_GroupMemberDAOLayer().getGroupMembersByGroupNames(groupNames);

        List<RES_EmailUtilityService> emailUtility = new List<RES_EmailUtilityService>();
        Set<String> templates = new Set<String>();

        String csoTemplate = SYSTEM.Label.Notify_CSO_Template;
        templates.add(csoTemplate);

        Map<String, RES_Apex_Email_Template__mdt> apexTemplates = new RES_ApexEmailTemplateDAO().getApexTemplateByName(templates);

        if(notifyCSO.size() > 0){
            if(apexTemplates.containsKey(csoTemplate)){
                RES_Apex_Email_Template__mdt csoTemplateRecord = apexTemplates.get(csoTemplate);
                String htmlBody = csoTemplateRecord.Html_Body__c;
                String subject = csoTemplateRecord.Subject__c;

                for(Notify node: notifyCSO){
                    if(groupToEmailsMapping.containsKey(node.recipientQueue)){
                        String fullName = node.leadInstance.FirstName + ' ' + node.leadInstance.LastName;
                        String leadUrl = URL.getOrgDomainUrl().toExternalForm()+ '/' + node.leadInstance.Id;

                        List<String> mergeFields = new List<String>(); mergeFields.add(fullName); 
                        mergeFields.add(node.leadInstance.MobilePhone); mergeFields.add(leadUrl);

                        for(String email: groupToEmailsMapping.get(node.recipientQueue)){
                            RES_EmailUtilityService utilNode = new RES_EmailUtilityService();
                            utilNode.setToAddresses(new List<String>{email});
                            utilNode.setHtmlBody(htmlBody,mergeFields);
                            utilNode.setOrgWideEmailAddressId(orgWideEmailAddressId);
                            utilNode.setSubject(subject);
                            emailUtility.add(utilNode);
                        }
                    }
                }
            }
        }
        try{
            RES_EmailService.sendEmail(emailUtility);
        }catch(Exception e){
            System.debug('Exception While Sending Duplicate Lead Emails ' + e.getMessage());
        }   
    }
}