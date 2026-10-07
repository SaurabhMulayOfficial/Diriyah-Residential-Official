/**
 * @description Cancels every open Quote (via QuoteLineItem) and Contract (via ContractItemPrice or the Quote's Contract)
 *              that uses a Residential Sales bundle unit moved from Available / Soft Hold / Hard Block back to Draft,
 *              revoking any in-progress approval on them with a system comment first.
 */
public without sharing class RES_UnitDraftCancellationService implements Queueable {

    private static final String DRAFT_STATUS = 'Draft';
    private static final String BUNDLE_TYPE = 'Bundle';
    private static final String CONTRACT_CANCELED_STATUS = 'Canceled';
    private static final String QUOTE_CANCELLED_STATUS = 'Cancelled';
    private static final String OPPORTUNITY_RESET_STAGE = 'Proposal';
    // Management Decision
    private static final String CONTRACT_CANCELLATION_REASON = '24';
    private static final Set<String> RELEASABLE_STATUSES = new Set<String>{ 'Available', 'Soft Hold', 'Hard Block' };
    private static final Set<String> CLOSED_QUOTE_STATUSES = new Set<String>{ 'Cancelled', 'Expired' };
    private static final Set<String> CLOSED_CONTRACT_STATUSES = new Set<String>{ 'Canceled', 'Terminated', 'Contract Terminated', 'Contract Expired' };
    private static final Id RESIDENTIAL_SALES_RECORD_TYPE_ID = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName()
        .get('RES_Residential_Sales')?.getRecordTypeId();

    private final Set<Id> unitIds;

    public RES_UnitDraftCancellationService(Set<Id> unitIds) {
        this.unitIds = unitIds;
    }

    public void execute(QueueableContext context) {
        cancelQuotesAndContracts(unitIds);
    }

    @TestVisible
    private static Boolean isMovingToDraft(Product2 newProduct, Product2 oldProduct) {
        return oldProduct != null
            && RESIDENTIAL_SALES_RECORD_TYPE_ID != null
            && newProduct.RecordTypeId == RESIDENTIAL_SALES_RECORD_TYPE_ID
            && newProduct.Type == BUNDLE_TYPE
            && newProduct.RES_Unit_Status__c == DRAFT_STATUS
            && RELEASABLE_STATUSES.contains(oldProduct.RES_Unit_Status__c);
    }

    /** @description Before update: clears the unit's reservation so cancelling its quotes/contracts (or the soft-hold expiry flow) can't flip it back to Available. */
    public static void releaseReservations(List<Product2> newProducts, Map<Id, Product2> oldMap) {
        for (Product2 p : newProducts) {
            if (!isMovingToDraft(p, oldMap.get(p.Id))) {
                continue;
            }
            p.RES_Reserved_By_Quote__c = null;
            p.RES_Reserved_By_Contract__c = null;
            p.RES_Soft_Hold_Start__c = null;
            p.RES_Soft_Hold_Until__c = null;
            p.RES_HardBlock_Start__c = null;
            p.RES_Is_In_Soft_Hold_Extension__c = false;
        }
    }

    /** @description After update: cancels quotes/contracts for units moved to Draft, async when a queueable slot is free. */
    public static void handleUnitsMovedToDraft(List<Product2> newProducts, Map<Id, Product2> oldMap) {
        Set<Id> draftUnitIds = new Set<Id>();
        for (Product2 p : newProducts) {
            if (isMovingToDraft(p, oldMap.get(p.Id))) {
                draftUnitIds.add(p.Id);
            }
        }
        if (draftUnitIds.isEmpty()) {
            return;
        }
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new RES_UnitDraftCancellationService(draftUnitIds));
        } else {
            cancelQuotesAndContracts(draftUnitIds);
        }
    }

    @TestVisible
    private static List<ApprovalSubmission> mockInProgressSubmissions;
    @TestVisible
    private static List<RES_Review_Approval_Work_Item__e> publishedReviewEvents = new List<RES_Review_Approval_Work_Item__e>();

    @TestVisible
    private static void cancelQuotesAndContracts(Set<Id> draftUnitIds) {
        Map<Id, Quote> quotesById = new Map<Id, Quote>();
        Set<Id> contractIds = new Set<Id>();
        Set<Id> primaryOpportunityIds = new Set<Id>();

        for (QuoteLineItem qli : new RES_QuoteLineItemDAO().getOpenQuoteLineItemsByProductIds(draftUnitIds, CLOSED_QUOTE_STATUSES)) {
            if (quotesById.containsKey(qli.QuoteId)) {
                continue;
            }
            Quote q = qli.Quote;
            quotesById.put(qli.QuoteId, q);
            if (q.ContractId != null && !CLOSED_CONTRACT_STATUSES.contains(q.Contract.Status)) {
                contractIds.add(q.ContractId);
            }
            if (q.IsSyncing && q.OpportunityId != null) {
                primaryOpportunityIds.add(q.OpportunityId);
            }
        }
        for (ContractItemPrice cip : new RES_ContractItemPriceDAOLayer().getOpenCIPByProductIds(draftUnitIds, CLOSED_CONTRACT_STATUSES)) {
            contractIds.add(cip.ContractId);
        }
        if (quotesById.isEmpty() && contractIds.isEmpty()) {
            return;
        }

        Set<Id> underApprovalIds = revokeApprovals(quotesById.keySet(), contractIds, primaryOpportunityIds);

        // Records still under approval are cancelled by RES_ReviewApprovalWorkItemService once the approval is revoked
        List<SObject> recordsToUpdate = new List<SObject>();
        for (Id quoteId : quotesById.keySet()) {
            if (!underApprovalIds.contains(quoteId)) {
                recordsToUpdate.add(new Quote(
                    Id = quoteId,
                    Status = QUOTE_CANCELLED_STATUS,
                    RES_Cancellation_Reason__c = System.Label.RES_Unit_Draft_Cancellation_Reason,
                    RES_Unit_Blocked_Start_Date__c = null,
                    RES_Unit_Blocked_End_Date__c = null
                ));
            }
        }
        for (Id opportunityId : primaryOpportunityIds) {
            if (!underApprovalIds.contains(opportunityId)) {
                recordsToUpdate.add(new Opportunity(Id = opportunityId, StageName = OPPORTUNITY_RESET_STAGE));
            }
        }
        contractIds.removeAll(underApprovalIds);
        for (Contract c : new RES_ContractDAOLayer().getContractsByIds(contractIds)) {
            Contract toCancel = new Contract(Id = c.Id, Status = CONTRACT_CANCELED_STATUS);
            if (String.isBlank(c.RES_Cancellation_Reasons__c)) {
                toCancel.RES_Cancellation_Reasons__c = CONTRACT_CANCELLATION_REASON;
            }
            recordsToUpdate.add(toCancel);
        }
        if (recordsToUpdate.isEmpty()) {
            return;
        }
        List<Database.SaveResult> results = Database.update(recordsToUpdate, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'RES_UnitDraftCancellationService cancel failed ' + recordsToUpdate[i].Id + ' ' + results[i].getErrors());
            }
        }
    }

    /** @description Revokes every in-progress approval on the quotes, contracts and primary-quote opportunities with a system comment; returns the records that were under approval. */
    private static Set<Id> revokeApprovals(Set<Id> quoteIds, Set<Id> contractIds, Set<Id> opportunityIds) {
        Set<Id> relatedIds = new Set<Id>(quoteIds);
        relatedIds.addAll(contractIds);
        relatedIds.addAll(opportunityIds);

        List<ApprovalSubmission> submissions = (Test.isRunningTest() && mockInProgressSubmissions != null)
            ? mockInProgressSubmissions
            : new RES_ProcessInstanceDAOLayer().getInProgressApprovalSubmissionsByRelatedRecordIds(relatedIds);

        Set<Id> underApprovalIds = new Set<Id>();
        List<RES_Review_Approval_Work_Item__e> reviewEvents = new List<RES_Review_Approval_Work_Item__e>();
        for (ApprovalSubmission submission : submissions) {
            Id recordId = submission.RelatedRecordId;
            underApprovalIds.add(recordId);
            RES_Review_Approval_Work_Item__e e = new RES_Review_Approval_Work_Item__e(
                RES_Approval_Decision__c = 'Cancel',
                RES_Approval_Comments__c = System.Label.RES_Unit_Draft_Approval_Recall_Comment,
                RES_Approval_Work_Item_Id__c = submission.Id
            );
            if (quoteIds.contains(recordId)) {
                e.RES_Post_Review_Action__c = 'QuoteCancellation';
                e.RES_QuoteId__c = recordId;
                e.RES_Cancellation_Reason__c = System.Label.RES_Unit_Draft_Cancellation_Reason;
            } else if (contractIds.contains(recordId)) {
                e.RES_Post_Review_Action__c = 'ContractCancellation';
                e.RES_recordId__c = recordId;
            } else {
                e.RES_Post_Review_Action__c = 'OpportunityStageTransition';
                e.RES_recordId__c = recordId;
            }
            reviewEvents.add(e);
        }
        if (!reviewEvents.isEmpty()) {
            publishedReviewEvents.addAll(reviewEvents);
            for (Database.SaveResult sr : EventBus.publish(reviewEvents)) {
                if (!sr.isSuccess()) {
                    System.debug(LoggingLevel.ERROR, 'RES_UnitDraftCancellationService approval revoke publish failed ' + sr.getErrors());
                }
            }
        }
        return underApprovalIds;
    }
}
