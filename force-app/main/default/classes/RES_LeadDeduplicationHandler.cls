/**
 * @ class name         : RES_LeadDeduplicationHandler
 * @ description        : This class is designed to handle the Lead Deduplication Logic.
 * @ author             : Saurabh Mulay
 */

public without sharing class RES_LeadDeduplicationHandler {

    public class LeadDuplicateWrapper {
        public Lead inputLead;
        public List<Lead> duplicateLeads = new List<Lead>();
        public Boolean hasDuplicates = false;
        public Boolean hasError = false;
        public List<String> errors = new List<String>();
        public Set<Id> duplicateLeadIds = new Set<Id>();
        public Map<String,List<Lead>> leadBySource = new Map<String,List<Lead>>();

        public LeadDuplicateWrapper(Lead inputLead) {
            this.inputLead = inputLead;
        }   
    }
    
    public static void apply(List<lead> leadList){

        if(leadList.isEmpty())return;
        List<LeadDuplicateWrapper> duplicateLeadsWrapper = getDuplicateLeads(leadList);

        duplicateLeadsWrapper = hydrateDuplicateWrapper(duplicateLeadsWrapper);

        System.debug(' Hydrated Duplicate Lead Wrapper ' + duplicateLeadsWrapper);
        runRuleEngine(duplicateLeadsWrapper);
    }

    public static List<LeadDuplicateWrapper> getDuplicateLeads(List<Lead> inputLeads) {

        List<LeadDuplicateWrapper> response = new List<LeadDuplicateWrapper>();

        if (inputLeads == null || inputLeads.isEmpty()) {
            return response;
        }

        for (Lead l : inputLeads) {
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


    public static boolean checkDaysThreshold(Lead existingLead, Lead inputLead, Integer daysThreshold){
        
        Datetime nowDate = (inputLead != null && inputLead.CreatedDate != null) 
        ? inputLead.CreatedDate 
        : Datetime.now();

        Date existingDate = existingLead.CreatedDate.date();
        Date compareDate = nowDate.date();

        Integer daysDiff = existingDate.daysBetween(compareDate);

        if(Math.abs(daysDiff) <= daysThreshold){
            return true;
        }
        return false;
    }

    public static String fieldEqualityCheck(Lead inputLead, List<Lead> existingLeadsByExistingSource, String fieldForEquality){
        String fieldValue = (String)inputLead.get(fieldForEquality);
        if(fieldValue == null || fieldValue == '')return 'NO VALUE';

        String assigningSameRm = '';

        for(Lead existingLead : existingLeadsByExistingSource){
            String existingFieldValue = (String) existingLead.get(fieldForEquality);
            if(String.valueOf(existingLead.OwnerId).startsWith('005')){
                assigningSameRm = String.valueOf(existingLead.OwnerId);
            }
            if(fieldValue == existingFieldValue){
                return 'SAME FOUND';
            }
        }

        return assigningSameRm;
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
            rule.Lead_Age_Threshold_Days__c == null &&
            String.isBlank(rule.Check_Field_Equality__c) &&
            String.isBlank(rule.Lead_Status__c);
    }

    public static Map<String, String> getLeadSourceMap() {
        Map<String, String> leadSourceMap = new Map<String, String>();
        if(leadSourceMap == null) {
            leadSourceMap = new Map<String, String>();
            for (Schema.PicklistEntry entry : Lead.LeadSource.getDescribe().getPicklistValues()) {
                leadSourceMap.put(entry.getValue(), entry.getLabel());
            }
        }
        return leadSourceMap;
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

                String fieldForEquality = rule.Check_Field_Equality__c;

                String incomingSource = source[0];
                String existingSource = source[1];

                if(inputLead.LeadSource != incomingSource)continue;

                Integer daysThreshold = (rule.Lead_Age_Threshold_Days__c == null) ? null : Integer.valueOf(rule.Lead_Age_Threshold_Days__c);

                String assignedTo = rule.Assigned_To__c != null ? rule.Assigned_To__c.toUpperCase() : '';
                String action = rule.Action__c != null ? rule.Action__c.toUpperCase() : '';

                if(leadBySource != null && leadBySource.containsKey(existingSource)){
                    System.debug('Rule Statisfied '  + ' '+ rule.Source__c + ' ' + rule.Lead_Age_Threshold_Days__c);
                    List<Lead> existingLeadsByExistingSource = leadBySource.get(existingSource);
                    String shouldArchive = rule.Lead_Status__c;

                    String displayIncomingSource = leadSourceMap.containsKey(incomingSource) ? leadSourceMap.get(incomingSource) : incomingSource;
                    String displayExistingSource = leadSourceMap.containsKey(existingSource) ? leadSourceMap.get(existingSource) : existingSource;
                    
                    //Anyway Block
                    if(isOnlyBlockRule(rule)){
                        System.debug('Simply Blocking by rule');
                        if(assignedTo == 'DIFFERENT'){
                            for(Lead l : existingLeadsByExistingSource){
                                if(l.OwnerId != null && String.valueOf(l.OwnerId).startsWith('005') && l.OwnerId != inputLead.OwnerId){
                                    inputLead.addError('Please review duplicates, The incoming Lead has '+ displayIncomingSource +' as Source and the existing duplicate Lead has ' + displayExistingSource + ' as a Source and the lead has been owned by a different RM.');
                                    break;
                                }
                            }
                        }
                        else{
                            inputLead.addError('Please review duplicates, The incoming Lead has '+ displayIncomingSource +' as Source and the existing duplicate Lead has ' + displayExistingSource + ' as a Source.');
                            break;
                        }
                    }

                    //Checking days Threshold
                    if(daysThreshold != null){
                        
                        Lead mostRecentLead;

                        for (Lead l : existingLeadsByExistingSource) {
                            if (l.Status == '01' || l.Status == '02') {
                                if (mostRecentLead == null || l.CreatedDate > mostRecentLead.CreatedDate) {
                                    mostRecentLead = l;
                                }
                            }
                        }
                        
                        if(mostRecentLead != null){
                            boolean shouldBlock =  checkDaysThreshold(mostRecentLead, inputLead, daysThreshold);
                            if(shouldBlock == true && action == 'BLOCK'){
                                System.debug('Days Threshold Statisfied ' + mostRecentLead.CreatedDate +' ' +mostRecentLead.Id);
                                inputLead.addError('Please Review duplicates, The existing Lead is created within ' + daysThreshold + ' days.');
                                break;
                            }
                        }
                    }

                    //Cheking field Equality
                    String checkFieldEquality = '';
                    
                    if(String.isNotBlank(fieldForEquality)){
                        checkFieldEquality = fieldEqualityCheck(inputLead, existingLeadsByExistingSource, fieldForEquality);

                        if(checkFieldEquality == 'SAME FOUND'){
                            if(action == 'BLOCK'){
                                System.debug('Blocking because the field value is same ' + checkFieldEquality);
                                inputLead.addError('Please review duplicates, The existing Lead has the same value for field ' + fieldForEquality);
                                break;
                            }
                        }
                        else if(checkFieldEquality.startsWith('005') && assignedTo == 'SAME'){
                            inputLead.OwnerId = checkFieldEquality;
                            break;
                        }
                    }

                    //Same RM assignment + archive the lead
                    String getSameRMId = getRmId(existingLeadsByExistingSource);

                    if(shouldArchive != null && shouldArchive != ''){
                        inputLead.Status = 'Archive';
                        if(getSameRMId != '' && assignedTo == 'SAME'){
                            inputLead.OwnerId = getSameRMId;
                        }
                        break;
                    }
                    else if(assignedTo == 'SAME' && getSameRMId != ''){
                        inputLead.OwnerId = getSameRMId;
                        break;
                    }
                }
            }
        }
    }
}