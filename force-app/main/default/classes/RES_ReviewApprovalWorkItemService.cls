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
        else if(filterByPostApprovalAction.containsKey('QuoteCancellation')){
            List<RES_Review_Approval_Work_Item__e> postQuoteApprovalEvents = filterByPostApprovalAction.get('QuoteCancellation');
            if(postQuoteApprovalEvents != null && postQuoteApprovalEvents.size() > 0){
                quoteCancellation(postQuoteApprovalEvents);
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