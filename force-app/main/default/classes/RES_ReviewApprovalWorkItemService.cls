/**
 * ==============================================================================
 * Class Name    : RES_ReviewApprovalWorkItemService
 * Description   : Processes Review Approval Work Item platform events and
 *                 executes post-review actions such as Quote Soft Hold and
 *                 Quote Cancellation while managing approval work items.
 * Author        : Saurabh Mulay
 * Company       : Globant Inc
 * ==============================================================================
 */

public with sharing class RES_ReviewApprovalWorkItemService {
    public RES_ReviewApprovalWorkItemService() {
    }

    public static void filter(List<RES_Review_Approval_Work_Item__e> events){
        Map<String, List<RES_Review_Approval_Work_Item__e>> filterByPostApprovalAction = new Map<String, List<RES_Review_Approval_Work_Item__e>>();

        for(RES_Review_Approval_Work_Item__e e: events){
            if(!filterByPostApprovalAction.containsKey(e.RES_Post_Review_Action__c)){
                filterByPostApprovalAction.put(e.RES_Post_Review_Action__c, new List<RES_Review_Approval_Work_Item__e>());
            }
            filterByPostApprovalAction.get(e.RES_Post_Review_Action__c).add(e);
        }

        if(filterByPostApprovalAction.containsKey('QuoteSoftHoldPostApproval')){
            List<RES_Review_Approval_Work_Item__e> postQuoteApprovalEvents = filterByPostApprovalAction.get('QuoteSoftHoldPostApproval');
            if(postQuoteApprovalEvents!= null && postQuoteApprovalEvents.size() > 0){
                runQuotePostApprovals(postQuoteApprovalEvents);
            }
        }
        if(filterByPostApprovalAction.containsKey('QuoteCancellation')){
            List<RES_Review_Approval_Work_Item__e> postQuoteApprovalEvents = filterByPostApprovalAction.get('QuoteCancellation');
            if(postQuoteApprovalEvents != null && postQuoteApprovalEvents.size() > 0){
                quoteCancellation(postQuoteApprovalEvents);
            }
        }
        if(filterByPostApprovalAction.containsKey('ContractCancellation')){
            List<RES_Review_Approval_Work_Item__e> postContractApprovalEvents = filterByPostApprovalAction.get('ContractCancellation');
            if(postContractApprovalEvents != null && postContractApprovalEvents.size() > 0){
                contractCancellation(postContractApprovalEvents);
            }
        }
        if(filterByPostApprovalAction.containsKey('OpportunityStageTransition')){
            List<RES_Review_Approval_Work_Item__e> postOpportunityApprovalEvents = filterByPostApprovalAction.get('OpportunityStageTransition');
            if(postOpportunityApprovalEvents != null && postOpportunityApprovalEvents.size() > 0){
                contractCancellation(postOpportunityApprovalEvents);
            }
        }
    }


    public static void runQuotePostApprovals(List<RES_Review_Approval_Work_Item__e> events){
        updateApprovalWorkItems(events);
        Set<Id> quoteIds = new Set<Id>();
        for(RES_Review_Approval_Work_Item__e e: events){
            if(e.RES_QuoteId__c != null){
                quoteIds.add(e.RES_QuoteId__c);
            }
        }

        List<Quote> quoteToUpdate = new List<Quote>();
        for(Id qId: quoteIds){
            Quote q = new Quote();
            q.Id = qId;
            q.RES_Product_Soft_Held__c = true;
            quoteToUpdate.add(q);
        }
        try{
            if(quoteToUpdate.size() > 0){
                Database.update(quoteToUpdate);
            }
        }catch(Exception e){
            System.debug('RES_ReviewApprovalWorkItemService.runQuotePostApprovals failed ' + e.getMessage());
        }
    }

    public static void quoteCancellation(List<RES_Review_Approval_Work_Item__e> events){
        updateApprovalWorkItems(events);
        Set<Id> quoteIds = new Set<Id>();
        for(RES_Review_Approval_Work_Item__e e: events){
            if(e.RES_QuoteId__c != null){
                quoteIds.add(e.RES_QuoteId__c);
            }
        }
        List<Quote> quoteToUpdate = new List<Quote>();
        for(Id qId: quoteIds){
            Quote q = new Quote();
            q.Id = qId;
            q.Status = 'Cancelled';
            q.RES_Unit_Blocked_Start_Date__c = null;
            q.RES_Unit_Blocked_End_Date__c = null;
            quoteToUpdate.add(q);
        }
        try{
            if(quoteToUpdate.size() > 0){
                Database.update(quoteToUpdate, false, AccessLevel.SYSTEM_MODE);
            }
        }catch(Exception e){
            System.debug('RES_ReviewApprovalWorkItemService.runQuotePostApprovals failed ' + e.getMessage());
        }
    }

    public static void contractCancellation(List<RES_Review_Approval_Work_Item__e> events){
        updateApprovalWorkItems(events);
        Set<Id> contractIds = new Set<Id>();
        for(RES_Review_Approval_Work_Item__e e: events){
            if(e.RES_recordId__c != null){
                contractIds.add(e.RES_recordId__c);
            }
        }
        List<Contract> contractToUpdate = new List<Contract>();
        for(Id cId: contractIds){
            Contract c = new Contract();
            c.Id = cId;
            c.Status = 'Canceled';
            contractToUpdate.add(c);
        }
        try{
            if(contractToUpdate.size() > 0){
                Database.update(contractToUpdate, false, AccessLevel.SYSTEM_MODE);
            }
        }catch(Exception e){
            System.debug('RES_ReviewApprovalWorkItemService.runQuotePostApprovals failed ' + e.getMessage());
        }
    }

    public static void opportunityStageTransition(List<RES_Review_Approval_Work_Item__e> events){
        updateApprovalWorkItems(events);
        Set<Id> opportunityIds = new Set<Id>();
        for(RES_Review_Approval_Work_Item__e e: events){
            if(e.RES_recordId__c != null){
                opportunityIds.add(e.RES_recordId__c);
            }
        }
        List<Opportunity> opportunityToUpdate = new List<Opportunity>();
        for(Id opId: opportunityIds){
            Opportunity op = new Opportunity();
            op.Id = opId;
            op.StageName = 'Proposal';
            opportunityToUpdate.add(op);
        }
        try{
            if(opportunityToUpdate.size() > 0){
                Database.update(opportunityToUpdate, false, AccessLevel.SYSTEM_MODE);
            }
        }catch(Exception e){
            System.debug('RES_ReviewApprovalWorkItemService.runQuotePostApprovals failed ' + e.getMessage());
        }
    }



    public static void updateApprovalWorkItems(List<RES_Review_Approval_Work_Item__e> events){
        List<RES_WorkItemFlowInput> workInputs = new List<RES_WorkItemFlowInput>();
        Set<Id> quoteIds = new Set<Id>();
        System.debug('UpdateApprovalWorkItems ' + events.size() + events);

        for(RES_Review_Approval_Work_Item__e e: events){
            RES_WorkItemFlowInput w = new RES_WorkItemFlowInput();
            w.action = e.RES_Approval_Decision__c;
            w.comment = e.RES_Approval_Comments__c;
            w.workitemId = e.RES_Approval_Work_Item_Id__c;
            workInputs.add(w);
        }

        try{
            RES_ApprovalWorkItemManagement.processWorkItems(workInputs);
        }catch(Exception e){
            System.debug('RES_ReviewApprovalWorkItemService.runQuotePostApprovals failed ' + e.getMessage());
        }
    }
}