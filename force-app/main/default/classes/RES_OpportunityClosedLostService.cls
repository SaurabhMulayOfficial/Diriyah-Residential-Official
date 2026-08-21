/**
 * ==============================================================================
 * Class Name    : RES_OpportunityClosedLostService
 * Description   : Flow-invocable service to process Closed Lost Opportunities.
 *
 *                 Cancels all Quotes related to the Opportunity (excluding those
 *                 currently Pending Approval, which the invoking Flow must
 *                 reject via its own Override Approval Work Item logic before
 *                 those Quotes can be cancelled) and releases associated Units
 *                 by changing their status from Soft Hold or Hard Block to
 *                 Available.
 *
 *                 The service also clears the applicable Soft Hold and
 *                 Hard Block date fields from the Unit.
 *
 *                 Quote Line Items are retrieved to identify the Products/Units
 *                 associated with the Opportunity.
 *
 *                 Units already in Available or Sold status are not released.
 *
 *                 A Product still actively referenced by a non-Cancelled Quote
 *                 on a DIFFERENT Opportunity (e.g., the same Unit quoted to a
 *                 backup buyer) is never released here — it is excluded from
 *                 the release step so it remains correctly held for that other,
 *                 still-live Quote.
 *
 *                 Pending approval work items and their parent process
 *                 instances are identified and returned to the Flow for it to
 *                 action directly — this service does NOT reject them itself.
 *
 *                 The service performs database updates in System Mode and
 *                 returns the Unit release / pending-approval identification
 *                 result to the invoking Flow.
 *
 * Author        : Roshan Jambhule
 * Company       : Globant Inc
 * Created Date  : Aug 13, 2026
 * Version       : 1.2
 * ==============================================================================
 */
public with sharing class RES_OpportunityClosedLostService {

    @TestVisible
    private static List<ApprovalWorkItem> mockPendingApprovalWorkItems = null;

    @InvocableMethod(label='Release Opportunity Units')
    public static List<Output> releaseUnits(List<Input> inputs) {
        Output output = new Output();
        output.unitsReleased = false;
        output.pendingApprovalQuotesFound = false;
        output.pendingApprovalQuoteIds = new List<Id>();
        output.pendingWorkItemIds = new List<Id>();

        if (inputs == null || inputs.isEmpty()) {
            return new List<Output>{ output };
        }
        try {
            // 1. Collect Opportunity Ids
            Set<Id> opportunityIds = new Set<Id>();
            for (Input inputRec : inputs) {
                if (inputRec != null && inputRec.opportunityId != null) {
                    opportunityIds.add(inputRec.opportunityId);
                }
            }
            if (opportunityIds.isEmpty()) {
                return new List<Output>{ output };
            }

            // 2. Query Quote Line Items first (needed to identify related products)
            List<QuoteLineItem> quoteLineItems = new RES_QuoteLineItemDAO().getQuoteLineItemsByOpportunity(opportunityIds);
            Set<Id> productIds = new Set<Id>();
            for (QuoteLineItem qli : quoteLineItems) {
                if (qli.Product2Id != null) {
                    productIds.add(qli.Product2Id);
                }
            }

            List<Product2> products = new List<Product2>();
            if (!productIds.isEmpty()) {
                products = new RES_Product2DAOLayer().getProductsByIds(productIds);
            }

            // 3. Query Quotes and split into buckets:
            //    - already Cancelled: skip
            //    - Pending Approval: DO NOT touch here — identify and report only,
            //      the Flow is responsible for rejecting these before this Quote
            //      can ever be cancelled (in a later run, once unlocked)
            //    - everything else: direct cancel, as before
            List<Quote> quotes = new RES_QuoteDAOLayer().getQuotesByOpportunityIds(opportunityIds);
            List<Quote> quotesPendingApproval = new List<Quote>();
            List<Quote> quotesToUpdate = new List<Quote>();

            for (Quote quote : quotes) {
                if (quote.Status == 'Cancelled') {
                    continue;
                }
                if (quote.Status == 'Pending Approval') {
                    quotesPendingApproval.add(quote);
                } else {
                    quote.Status = 'Cancelled';
                    quotesToUpdate.add(quote);
                }
            }

            // 3a. For Quotes stuck mid-approval, identify their pending work items
            //     and report the Ids back to Flow — no action taken here.
            if (!quotesPendingApproval.isEmpty()) {
                Set<Id> pendingQuoteIds = new Set<Id>();
                for (Quote q : quotesPendingApproval) {
                    pendingQuoteIds.add(q.Id);
                }

                List<ApprovalWorkItem> pendingItems = (Test.isRunningTest() && mockPendingApprovalWorkItems != null) ? mockPendingApprovalWorkItems : new RES_ProcessInstanceDAOLayer().getPendingWorkItemsByTargetIds(pendingQuoteIds, 'Quote');
                
                if (!pendingItems.isEmpty()) {
                    output.pendingApprovalQuotesFound = true;
                    for (Quote q : quotesPendingApproval) {
                        output.pendingApprovalQuoteIds.add(q.Id);
                    }

                    List<RES_Review_Approval_Work_Item__e> eventsToPublish = new List<RES_Review_Approval_Work_Item__e>();
                    Set<Id> publishIds = new Set<Id>();
                    for (ApprovalWorkItem wi : pendingItems) {
                        if(publishIds.contains(wi.id)){
                            continue;
                        }
                        RES_Review_Approval_Work_Item__e eventRecord = new RES_Review_Approval_Work_Item__e();
                        eventRecord.RES_Approval_Decision__c = 'Cancel';
                        eventRecord.RES_Approval_Comments__c = System.Label.RES_Auto_Reject_On_Cancel_Opportunity;
                        eventRecord.RES_Approval_Work_Item_Id__c = wi.ApprovalSubmissionId;
                        eventRecord.RES_QuoteId__c = wi.RelatedRecordId;
                        eventRecord.RES_Post_Review_Action__c = 'QuoteCancellation';
                        publishIds.add(wi.id);
                        eventsToPublish.add(eventRecord);
                        output.pendingWorkItemIds.add(wi.Id);
                    }
                    try {
                        EventBus.publish(eventsToPublish);
                    } catch (Exception e) {
                        System.debug('Error occurred while publishing events: ' + e.getMessage());
                    }
                }
            }

            // 3b. Guard against releasing Units still actively quoted on OTHER
            //     Opportunities. A Product can legitimately appear on multiple
            //     Quotes across different Opportunities (e.g., backup buyer
            //     scenarios) — only release it if no other non-Cancelled Quote
            //     elsewhere still references it.
            Set<Id> productIdsStillHeldElsewhere = new Set<Id>();
            if (!productIds.isEmpty()) {
                List<QuoteLineItem> conflictingQLIs =
                    new RES_QuoteLineItemDAO().getActiveQuoteLineItemsByProductIdsExcludingOpportunities(
                        productIds, opportunityIds
                    );
                for (QuoteLineItem qli : conflictingQLIs) {
                    productIdsStillHeldElsewhere.add(qli.Product2Id);
                }
            }

            // 4. Release Units — unrelated to Quote approval state, always attempted
            //    (except Units still held elsewhere per the guard above)
            if (!products.isEmpty()) {
                List<Product2> productsToUpdate = new List<Product2>();
                for (Product2 product : products) {
                    if (productIdsStillHeldElsewhere.contains(product.Id)) {
                        continue; // still actively quoted on another, non-Cancelled Quote elsewhere
                    }
                    Boolean isChanged = false;
                    if (
                        product.RES_Unit_Status__c == 'Soft Hold' ||
                        product.RES_Unit_Status__c == 'Hard Block'
                    ) {
                        product.RES_Unit_Status__c = 'Available';
                        product.RES_Is_In_Soft_Hold_Extension__c = false;
                        product.RES_Soft_Hold_Start__c = null;
                        product.RES_Soft_Hold_Until__c = null;
                        isChanged = true;
                    }
                    if (product.RES_HardBlock_Start__c != null) {
                        product.RES_HardBlock_Start__c = null;
                        isChanged = true;
                    }
                    if (isChanged) {
                        productsToUpdate.add(product);
                    }
                }

                if (!productsToUpdate.isEmpty()) {
                    Database.SaveResult[] productResults =
                        Database.update(productsToUpdate, false, AccessLevel.SYSTEM_MODE);
                    for (Integer i = 0; i < productResults.size(); i++) {
                        if (productResults[i].isSuccess()) {
                            output.unitsReleased = true;
                        } else {
                            for (Database.Error error : productResults[i].getErrors()) {
                                System.debug(
                                    LoggingLevel.ERROR,
                                    'Product update failed. Product Id: '
                                    + productsToUpdate[i].Id
                                    + ' | Error: '
                                    + error.getMessage()
                                );
                            }
                        }
                    }
                }
            }

            // 5. Cancel Quotes LAST — only the direct-cancel bucket.
            //    Pending-approval Quotes are intentionally excluded here; they
            //    remain untouched until the Flow rejects their work item and
            //    this action is invoked again (or a follow-up Update Records
            //    element in the same Flow run sets Status = Cancelled after
            //    the Override action succeeds).
            if (!quotesToUpdate.isEmpty()) {
                Database.SaveResult[] quoteResults =
                    Database.update(quotesToUpdate, false, AccessLevel.SYSTEM_MODE);
                for (Integer i = 0; i < quoteResults.size(); i++) {
                    if (!quoteResults[i].isSuccess()) {
                        for (Database.Error error : quoteResults[i].getErrors()) {
                            System.debug(
                                LoggingLevel.ERROR,
                                'Quote cancellation failed. Quote Id: '
                                + quotesToUpdate[i].Id
                                + ' | Error: '
                                + error.getMessage()
                            );
                        }
                    }
                }
            }

            return new List<Output>{ output };

        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'RES_OpportunityClosedLostService failed. '
                + 'Message: ' + ex.getMessage()
                + ' | Line: ' + ex.getLineNumber()
            );
            throw new AuraHandledException(
                'Error while releasing Units and cancelling Quotes: '
                + ex.getMessage()
            );
        }
    }

    public class Input {
        @InvocableVariable(required=true)
        public Id opportunityId;
    }

    public class Output {
        @InvocableVariable
        public Boolean unitsReleased;

        @InvocableVariable
        public Boolean pendingApprovalQuotesFound;

        @InvocableVariable
        public List<Id> pendingApprovalQuoteIds;

        @InvocableVariable
        public List<Id> pendingWorkItemIds;
    }
}