/**
 * Flow-invocable service to cancel Quotes, Contracts and release Units when Opportunity is Closed Lost.
 * Handles pending approval quotes, guards against releasing units held by other opportunities.
 *
 * Author: Roshan Jambhule | Globant Inc
 * Version: 1.5 | Sept 09, 2026 - Enhanced approval work item handling for both Quotes and Contracts (DIR-XXXX)
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
            Set<Id> opportunityIds = new Set<Id>();
            for (Input inputRec : inputs) {
                if (inputRec != null && inputRec.opportunityId != null) {
                    opportunityIds.add(inputRec.opportunityId);
                }
            }
            if (opportunityIds.isEmpty()) {
                return new List<Output>{ output };
            }

            List<QuoteLineItem> quoteLineItems = new RES_QuoteLineItemDAO().getAllQuoteLineItemsByOpportunityIncludingSoftHeld(opportunityIds);
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

            List<Quote> quotes = new RES_QuoteDAOLayer().getQuotesByOpportunityIds(opportunityIds);
            List<Quote> quotesPendingApproval = new List<Quote>();
            List<Quote> quotesToUpdate = new List<Quote>();
            Set<Id> quoteIdsForApprovalCheck = new Set<Id>();

            // First pass: Collect quote IDs for approval work item check BEFORE modifying status
            for (Quote quote : quotes) {
                if (quote.Status != 'Cancelled') {
                    quoteIdsForApprovalCheck.add(quote.Id);
                }
            }

            // Second pass: Categorize quotes and prepare for cancellation
            for (Quote quote : quotes) {
                if (quote.Status == 'Cancelled') {
                    continue;
                }
                if (quote.Status == 'Pending Approval') {
                    quotesPendingApproval.add(quote);
                } else {
                    quote.Status = 'Cancelled';
                    quote.RES_Unit_Blocked_Start_Date__c = null;
                    quote.RES_Unit_Blocked_End_Date__c = null;
                    quote.RES_Cancellation_Reason__c = System.Label.RES_Default_Cancellation_Reason;
                    quotesToUpdate.add(quote);
                }
            }

            // Cancel related contracts
            List<Contract> contracts = new RES_ContractDAOLayer().getContractsByOpportunityIds(opportunityIds);
            List<Contract> contractsToUpdate = new List<Contract>();
            for (Contract contract : contracts) {
                if (contract.Status != 'Canceled') {
                    contract.Status = 'Canceled';
                    contractsToUpdate.add(contract);
                }
            }

            // Handle approval work items for both Quotes and Contracts
            Set<Id> relatedRecordIds = new Set<Id>();

            // Add quote IDs collected BEFORE status modification
            relatedRecordIds.addAll(quoteIdsForApprovalCheck);

            // Add contract IDs that may have pending approvals
            for (Contract contract : contracts) {
                relatedRecordIds.add(contract.Id);
            }

            if (!relatedRecordIds.isEmpty()) {
                List<ApprovalWorkItem> pendingItems = (Test.isRunningTest() && mockPendingApprovalWorkItems != null)
                    ? mockPendingApprovalWorkItems
                    : new RES_ProcessInstanceDAOLayer().getApprovalWorkItemByRelatedRecordIds(relatedRecordIds);

                if (!pendingItems.isEmpty()) {
                    output.pendingApprovalQuotesFound = true;

                    // Collect quote IDs that have actual work items
                    Set<Id> quotesWithWorkItems = new Set<Id>();
                    for (ApprovalWorkItem wi : pendingItems) {
                        String relatedRecordId = String.valueOf(wi.RelatedRecordId);
                        if (relatedRecordId.startsWith('0Q0')) {
                            quotesWithWorkItems.add(wi.RelatedRecordId);
                        }
                    }

                    // Only add quotes to output if they have work items
                    if (!quotesPendingApproval.isEmpty()) {
                        for (Quote q : quotesPendingApproval) {
                            if (quotesWithWorkItems.contains(q.Id)) {
                                output.pendingApprovalQuoteIds.add(q.Id);
                            }
                        }
                    }

                    List<RES_Review_Approval_Work_Item__e> eventsToPublish = new List<RES_Review_Approval_Work_Item__e>();
                    Set<Id> approvalSubmissionIds = new Set<Id>();

                    for (ApprovalWorkItem wi : pendingItems) {
                        // Skip if already processed
                        if (approvalSubmissionIds.contains(wi.ApprovalSubmissionId)) {
                            continue;
                        }

                        RES_Review_Approval_Work_Item__e eventRecord = new RES_Review_Approval_Work_Item__e();
                        eventRecord.RES_Approval_Decision__c = 'Cancel';
                        eventRecord.RES_Approval_Comments__c = System.Label.RES_Auto_Reject_On_Cancel_Opportunity;
                        eventRecord.RES_Approval_Work_Item_Id__c = wi.ApprovalSubmissionId;

                        // Determine object type and set appropriate action (reusing QuoteCancellationService pattern)
                        String relatedRecordId = String.valueOf(wi.RelatedRecordId);

                        if (relatedRecordId.startsWith('800')) {
                            // Contract approval
                            eventRecord.RES_Post_Review_Action__c = 'ContractCancellation';
                            eventRecord.RES_recordId__c = wi.RelatedRecordId;
                        } else if (relatedRecordId.startsWith('0Q0')) {
                            // Quote approval
                            eventRecord.RES_Post_Review_Action__c = 'QuoteCancellation';
                            eventRecord.RES_QuoteId__c = wi.RelatedRecordId;
                            eventRecord.RES_Cancellation_Reason__c = System.Label.RES_Default_Cancellation_Reason;
                        }

                        approvalSubmissionIds.add(wi.ApprovalSubmissionId);
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

            if (!products.isEmpty()) {
                List<Product2> productsToUpdate = new List<Product2>();
                for (Product2 product : products) {
                    if (productIdsStillHeldElsewhere.contains(product.Id)) {
                        continue;
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
                        product.RES_Reserved_By_Contract__c = null;
                        product.RES_Reserved_By_Quote__c = null;
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

            if (!contractsToUpdate.isEmpty()) {
                Database.SaveResult[] contractResults =
                    Database.update(contractsToUpdate, false, AccessLevel.SYSTEM_MODE);
                for (Integer i = 0; i < contractResults.size(); i++) {
                    if (!contractResults[i].isSuccess()) {
                        for (Database.Error error : contractResults[i].getErrors()) {
                            System.debug(
                                LoggingLevel.ERROR,
                                'Contract cancellation failed. Contract Id: '
                                + contractsToUpdate[i].Id
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