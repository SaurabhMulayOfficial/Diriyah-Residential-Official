/**
 * ==============================================================================
 * Class Name    : RES_ProductOrchestrator
 * Description   : Service class responsible for orchestrating Product/Unit
 *                 Soft Hold processing for Opportunities.
 *
 *                 Identifies the Products/Units associated with the provided
 *                 Opportunities through Quote Line Items and applies a Soft Hold
 *                 to those Units.
 *
 *                 The service also identifies other Quotes containing the same
 *                 Products/Units and marks them as Product Soft Held.
 *
 *                 The Soft Hold duration is determined from the
 *                 Soft_Hold_Window custom label and the default Business Hours
 *                 configuration.
 *
 *                 The associated Unit is updated with the Soft Hold start date,
 *                 Soft Hold expiry date, and the Quote responsible for the hold.
 *
 * Author        : Saurabh Mule
 * Company       : Globant Inc
 * Created Date  : Aug 13, 2026
 * Version       : 1.0
 * ============================================================================== 
 * **/
public without sharing class RES_ProductOrchestrator {
    public RES_ProductOrchestrator() {}

    public static void applySoftHold(List<Opportunity> OpportunityList){
        Set<Id> oppIds = new Set<Id>();
        for(Opportunity op: OpportunityList){
            oppIds.add(op.Id);
        }
        if(oppIds.size() <= 0)return;

        List<QuoteLineItem> quoteLineItems = new RES_QuoteLineItemDAO().getQuoteLineItemsByOpportunity(oppIds);

        if(quoteLineItems.size() <= 0)return;
        
        Map<Id, Id> productBlockedBy = new Map<Id, Id>();

        for(QuoteLineItem qli: quoteLineItems){
            if(qli.Quote.IsSyncing && !productBlockedBy.containsKey(qli.Product2Id)) {
                productBlockedBy.put(qli.Product2Id, qli.QuoteId);
            }
        }

        List<QuoteLineItem> allRelatedQuoteLineItems = new RES_QuoteLineItemDAO().getQuoteLineItemsByProductIds(productBlockedBy.keySet());
        Set<Id> quotesIds = new Set<Id>();
        for(QuoteLineItem qli: allRelatedQuoteLineItems){
            if(productBlockedBy.containsKey(qli.Product2Id) && qli.QuoteId != productBlockedBy.get(qli.Product2Id)){
                quotesIds.add(qli.QuoteId);
            }
        }
        List<Quote> quotesToUpdate = new List<Quote>();
        for(Id quoteId: quotesIds){
            Quote q = new Quote(Id = quoteId);
            q.RES_Product_Soft_Held__c = true;
            quotesToUpdate.add(q);
        }

        // Start EVENT -----------------------
        List<ApprovalWorkItem> approvalWorkItems = new RES_ProcessInstanceDAOLayer().getApprovalWorkItems(quotesIds, 'Soft Hold Extension Approvals');
        if(approvalWorkItems.size() > 0){
            List<RES_Review_Approval_Work_Item__e> events = new List<RES_Review_Approval_Work_Item__e>();
            for(ApprovalWorkItem awi: approvalWorkItems){
                RES_Review_Approval_Work_Item__e e = new RES_Review_Approval_Work_Item__e();
                e.RES_Approval_Work_Item_Id__c = awi.Id;
                e.RES_Approval_Decision__c = 'Reject';
                e.RES_Approval_Comments__c = SYSTEM.Label.RES_Soft_Hold_Reject;
                e.RES_QuoteId__c = awi.RelatedRecordId;
                e.RES_Post_Review_Action__c = 'QuoteSoftHoldPostApproval';
                events.add(e);
            }

            try{
                EventBus.publish(events);
            }catch(Exception e){
                System.debug('Approval Work Item Failed To Reject ' + e.getMessage());
            }
        }
        //End EVENT --------------------------

        Integer softHoldWindow = 8;
        String softHoldWindowLabel = SYSTEM.Label.Soft_Hold_Window;
        if(String.isNotBlank(softHoldWindowLabel)){
            softHoldWindow = Integer.valueOf(softHoldWindowLabel);
        }

        List<BusinessHours> businessHourLst = new RES_BusinessHoursDAOLayer().getDefaultBusinessHours();
        List<Product2> productsToUpdate = new List<Product2>();
        for(Id productId: productBlockedBy.keySet()){
            Product2 p = new Product2(Id = productId);
            p.RES_Unit_Status__c = 'Soft Hold';
            p.RES_Soft_Hold_Start__c = System.now();
            Long interval = (Long)softHoldWindow * 60 * 60 * 1000;
            p.RES_Soft_Hold_Until__c = BusinessHours.add(businessHourLst[0].Id, System.now(), interval);
            p.RES_Reserved_By_Quote__c = productBlockedBy.get(productId);
            p.RES_Is_In_Soft_Hold_Extension__c = false;
            productsToUpdate.add(p);
        }

        try{
            Database.update(productsToUpdate, false, AccessLevel.SYSTEM_MODE);
        }
        catch(Exception e){
            System.debug('Error occurred while updating products: ' + e.getMessage());
        }

        Set<Id> blockedQuotes = new Set<Id>(productBlockedBy.values());
        
        if(blockedQuotes.size() > 0){
            for(Id key: blockedQuotes){
                Quote q = new Quote();
                q.Id = key;
                q.RES_Unit_Blocked_Start_Date__c = System.now();
                Long interval = (Long)softHoldWindow * 60 * 60 * 1000;
                q.RES_Unit_Blocked_End_Date__c = BusinessHours.add(businessHourLst[0].Id, System.now(), interval);
                quotesToUpdate.add(q);
            }

            try{
                if(quotesToUpdate.size() > 0){
                    Database.update(quotesToUpdate, false, AccessLevel.SYSTEM_MODE);
                }
            }catch(Exception e){
                System.debug('Exception Updating Reserved Quotes ' + e.getMessage());
            }
        }
    }
}