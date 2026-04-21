public with sharing class RES_ReassignmentLogicHandler {
    public static Map<Id, RecordType> recordTypes = new Map<Id, RecordType>();
    public static Map<Id, RES_Assignment_Config__c> configMap = new Map<Id, RES_Assignment_Config__c>();
    public static Map<String, Id> queueNameToIdMapping = new Map<String, Id>();


    public class leadRoutingWrapper{
        public  Lead leadRecord;
        public  RES_Assignment_Rule__c rule;

        public leadRoutingWrapper(Lead leadRecord, RES_Assignment_Rule__c rule){
            this.leadRecord = leadRecord;
            this.rule = rule;
        }
    }
    public class ReassignmentNode{
        public Id ConfigId;
        public Id queueId;
        public List<Lead> leadToReassign;
        public ReassignmentNode(Id configId){
            this.ConfigId = configId;
            this.leadToReassign = new List<Lead>();
        }
    }

    public static void runLeadReassignment(List<Lead> leadList, List<leadRoutingWrapper> routingUpdates){
        Map<Id, List<RES_Assignment_Rule__c>> assignmentRulesByConfig = preprocessLeadsForReassignment(leadList);
        List<ReassignmentNode> reassignmentNodeList = hydrateReassignmentNodes(leadList,assignmentRulesByConfig);
        runReassignment(reassignmentNodeList, assignmentRulesByConfig, routingUpdates);
        clearStaticVariables();
    }   

    public static  Map<Id, List<RES_Assignment_Rule__c>>  preprocessLeadsForReassignment(List<Lead> leadList){
        if(leadList == null || leadList.isEmpty()){
            return null;
        }
        Set<id> recordTypeIds = new Set<id>();
        for(lead l: leadList){
            recordTypeIds.add(l.RecordTypeId);
        }

        recordTypes = new RES_RecordTypeDAO().getRecordTypes(recordTypeIds,'Lead');
        Set<String> recordTypeNames = new Set<String>();

        for(RecordType rt : recordTypes.values()){
            recordTypeNames.add(rt.developerName);
        }

        List<RES_Assignment_Config__c> configs = new RES_AssignmentConfigDAO().getActiveAssignmentConfigs(recordTypeNames);
        System.debug('Configs fetched for reassignment'+ configs);
        Set<Id> configIds = new Set<Id>();
        for(RES_Assignment_Config__c config : configs){
            configIds.add(config.Id);
        }

        Set<String> fallbackQueues = new Set<String>();

        for(RES_Assignment_Config__c config : configs){
            configMap.put(config.Id, config);
            fallbackQueues.add(config.RES_Queue__c);
        }

        Map<Id, List<RES_Assignment_Rule__c>> assignmentRulesByConfig = new RES_AssignmentRuleDAO().getAssignmentRuleByConfig(configIds);
        queueNameToIdMapping = new RES_GroupDAOLayer().getQueueMappingbyIds(fallbackQueues);
        System.debug('Queue Name to Id Mapping'+ queueNameToIdMapping);
        return assignmentRulesByConfig;
    }


    public static Id evaluateLeadForReassignment(Lead l){
        String rtName = '';
        if(recordTypes.containsKey(l.RecordTypeId)){
            rtName = recordTypes.get(l.RecordTypeId).developerName;
        }

        for(RES_Assignment_Config__c config: configMap.values()){
            Set<String> channels = new Set<String>(config.RES_Channel__c.split(';'));
            Set<String> recordTypeSet = new Set<String>(config.RES_Record_Types__c.split(';'));

            if(channels.contains(l.LeadSource) && recordTypeSet.contains(rtName)){
                System.debug('Matching config found for lead with Record Type '+ rtName + ' and Lead Source '+ l.LeadSource + ' Config Id '+ config.Id);
                return config.Id;
            }
        }
        system.debug('No matching config found for lead with Record Type '+ rtName + ' and Lead Source '+ l.LeadSource);

        return null;
    }
    
    public static List<ReassignmentNode> hydrateReassignmentNodes(List<Lead> leadList, Map<Id, List<RES_Assignment_Rule__c>> assignmentRulesByConfig){
        Map<String,ReassignmentNode> nodeMapping = new Map<String, ReassignmentNode>();

        for(Lead l: leadList){
            Id configId = evaluateLeadForReassignment(l);
            System.debug('Record Type Name '+ configId);

            if(configId == null)continue;

            if(!nodeMapping.containsKey(configId)){
                nodeMapping.put(configId, new ReassignmentNode(configId));
                RES_Assignment_Config__c config = configMap.get(configId);
            
                if(config == null){
                    system.debug('No config found for config Id '+ configId);
                }
                
                String queueName = config.RES_Queue__c;
                Id queueId = null;
                
                if(queueNameToIdMapping.containsKey(queueName)){
                    queueId = queueNameToIdMapping.get(queueName);
                }
                System.debug('Queue Id for Lead '+ queueId);
                nodeMapping.get(configId).queueId = queueId;
            }

            ReassignmentNode node = nodeMapping.get(configId);
            node.leadToReassign.add(l);
        }

        List<ReassignmentNode> listOfReassignmentNodes = new List<ReassignmentNode>();
        for(String key: nodeMapping.keySet()){
            listOfReassignmentNodes.add(nodeMapping.get(key));
        }
        return listOfReassignmentNodes;
    }


    public static void runReassignment(List<ReassignmentNode> reassignmentNodes, Map<Id, List<RES_Assignment_Rule__c>> assignmentRulesByConfig, List<leadRoutingWrapper> routingUpdates){
        system.debug('Running Reassignment Logic'+ reassignmentNodes + 'Assignment Rules by Config'+ assignmentRulesByConfig);
        for(ReassignmentNode node: reassignmentNodes){

            Id configId = node.ConfigId;
            Id queueId = node.queueId;

            List<Lead> inputLeadList = node.leadToReassign;
            system.debug('config Id and QueueId'+ configId + queueId);

            if(!assignmentRulesByConfig.containskey(configId)){
                continue;
            }

            List<RES_Assignment_Rule__c> assignmentRule = assignmentRulesByConfig.get(configId);

            if(assignmentRule == null || assignmentRule.isEmpty()){
                for(Lead l: inputLeadList){
                    l.OwnerId = queueId;
                }

                System.debug('No Assignment Rule found Assigning every lead to QUEUE');
                continue;
            }

            Integer currentIndex = 0;
            Integer N = assignmentRule.size();
            
            for(Integer i = 0; i<N; i++){
                if(assignmentRule[i].RES_Last_Assigned__c == true){
                    currentIndex = Math.mod(i+1, N);
                    break;
                }
            }
            

            Integer i = 0;
            Set<Integer> visitedFullCapacity = new Set<Integer>();

            while(i < inputLeadList.size()){
                if(visitedFullCapacity.size() == N){
                    inputLeadList[i].OwnerId = queueId;
                    i+=1;
                    continue;
                }
                
                Lead currentLead = inputLeadList[i];

                RES_Assignment_Rule__c currentRule = assignmentRule[currentIndex];
                currentRule.RES_Last_Assigned__c = true;
                Integer leadCount = currentRule.RES_Lead_Count__c == null ? 0 : Integer.valueOf(currentRule.RES_Lead_Count__c);
                Integer capacity = (Integer) currentRule.RES_Capacity__c;

                if(leadCount < capacity){
                    currentLead.OwnerId = currentRule.RES_User__c;
                    routingUpdates.add(new leadRoutingWrapper(currentLead, currentRule));
                    currentIndex = Math.mod( currentIndex + 1, N );
                    i+=1;
                }
                else{
                    visitedFullCapacity.add(currentIndex);
                    currentIndex = Math.mod( currentIndex + 1, N );
                } 
            } 

            for(RES_Assignment_Rule__c ar: assignmentRule){
                ar.RES_Last_Assigned__c = false;
            }

            Integer lastIndex = Math.mod(currentIndex - 1 + N, N);
            assignmentRule[lastIndex].RES_Last_Assigned__c = true;
        }

        List<RES_Assignment_Rule__c> rulesToUpdate = new List<RES_Assignment_Rule__c>();
        for(Id key: assignmentRulesByConfig.keySet()){
            if(assignmentRulesByConfig.get(key) != null && assignmentRulesByConfig.get(key).size() > 0){
                for(RES_Assignment_Rule__c ar: assignmentRulesByConfig.get(key)){
                    rulesToUpdate.add(ar);
                }
            }
        }

        try{
            Database.update(rulesToUpdate, true, AccessLevel.SYSTEM_MODE);
        }catch(Exception e){
            System.debug('Exception while updating records' + e.getMessage());
        }
    }


    public static void updateRoutingRecords(List<leadRoutingWrapper> routingUpdates){
        List<RES_Lead_Routing__c> routingRecords = new List<RES_Lead_Routing__c>();
        for(leadRoutingWrapper wrapper: routingUpdates){
            Id leadId = wrapper.leadRecord.Id;
            Id ruleId = wrapper.rule.Id;
            routingRecords.add(new RES_Lead_Routing__c(
                RES_Lead__c = leadId,
                RES_Assignment_Rule__c = ruleId
            ));

        }
        try{
            Database.insert(routingRecords, true, AccessLevel.SYSTEM_MODE);
        }catch(Exception e){
            System.debug('Exception while inserting routing records' + e.getMessage());
        }
    }

    public static void clearStaticVariables(){
        recordTypes.clear();
        configMap.clear();
        queueNameToIdMapping.clear();
    }
}