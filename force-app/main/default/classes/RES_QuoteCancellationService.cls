public without sharing class RES_QuoteCancellationService {
    public RES_QuoteCancellationService() {}
    public class input{
        @InvocableVariable(required = true)
        public Quote quoteInstance;
    }

    @InvocableMethod(label='Quote Cancellation Service' description='Cancel Quotes')
    public static void cancelQuotations(List<input> inputs){
        Set<Id> relatedRecordIds = new Set<Id>();
        Set<Id> quoteIds = new Set<Id>();
        Map<Id, Quote> opportunityToQuoteMapping = new Map<Id, Quote>();
        Map<Id, String> quoteToCancellationReason = new Map<Id, String>();


        for(input iterator: inputs){
            relatedRecordIds.add(iterator.quoteInstance.Id);
            quoteIds.add(iterator.quoteInstance.Id);
            quoteToCancellationReason.put(iterator.quoteInstance.Id, iterator.quoteInstance.RES_Cancellation_Reason__c);

            if(iterator.quoteInstance.ContractId != null){
                relatedRecordIds.add(iterator.quoteInstance.ContractId);
            }
            if(iterator.quoteInstance.OpportunityId != null){
                relatedRecordIds.add(iterator.quoteInstance.OpportunityId);
            }
            if(iterator.quoteInstance.OpportunityId != null){
                opportunityToQuoteMapping.put(iterator.quoteInstance.OpportunityId, iterator.quoteInstance);
            }
        }

        List<ApprovalWorkItem> pendingItems = new RES_ProcessInstanceDAOLayer().getApprovalWorkItemByRelatedRecordIds(relatedRecordIds);
        Set<Id> processedIds = new Set<Id>();

        if(pendingItems.size() > 0){
            Set<Id> approvalSubmissionIds = new Set<Id>();
            List<RES_Review_Approval_Work_Item__e> reviewItems = new List<RES_Review_Approval_Work_Item__e>();
            for(ApprovalWorkItem awi: pendingItems){
                processedIds.add(awi.RelatedRecordId);
                if(approvalSubmissionIds.contains(awi.ApprovalSubmissionId)){
                    continue;
                }
                RES_Review_Approval_Work_Item__e e = new RES_Review_Approval_Work_Item__e();
                String relatedRecordId = String.valueOf(awi.RelatedRecordId);

                if (relatedRecordId.startsWith('800')) {
                    e.RES_Post_Review_Action__c = 'ContractCancellation';
                    e.RES_recordId__c = awi.RelatedRecordId;
                } else if (relatedRecordId.startsWith('006')) {
                    Quote q = opportunityToQuoteMapping.get(awi.RelatedRecordId);
                    if(q != null && q.IsSyncing == false){
                        continue;
                    }
                    e.RES_Post_Review_Action__c = 'OpportunityStageTransition';
                    e.RES_recordId__c = awi.RelatedRecordId;
                } else if (relatedRecordId.startsWith('0Q0')) {
                    e.RES_Post_Review_Action__c = 'QuoteCancellation';
                    e.RES_QuoteId__c = awi.RelatedRecordId;
                    String cancellationReason = quoteToCancellationReason.get(awi.RelatedRecordId);
                    if(cancellationReason == null){
                        cancellationReason = SYSTEM.Label.RES_Default_Cancellation_Reason;
                    }
                    e.RES_Cancellation_Reason__c = cancellationReason;
                }

                e.RES_Approval_Comments__c = SYSTEM.Label.RES_Approvals_Auto_Cancelled;
                e.RES_Approval_Decision__c = 'Cancel';
                e.RES_Approval_Work_Item_Id__c = awi.ApprovalSubmissionId;
                approvalSubmissionIds.add(awi.ApprovalSubmissionId);
                reviewItems.add(e);
            }

            try{
                EventBus.publish(reviewItems);
            }
            catch(Exception e){
                System.debug('Approvals Auto Cancelled Failed RES_QuoteCancellationService.cancelQuotations ' + e.getMessage());
            }
        }

        List<SObject> recordsToUpdate = new List<SObject>();
        for(input itr: inputs){
            Id quoteId = itr.quoteInstance.Id;
            Id relatedContractId = itr.quoteInstance.ContractId;
            Id relatedOpportunityId = itr.quoteInstance.OpportunityId;
            String cancellationReason = String.isBlank(itr.quoteInstance.RES_Cancellation_Reason__c)
                                            ? System.Label.RES_Default_Cancellation_Reason
                                            : itr.quoteInstance.RES_Cancellation_Reason__c;

            Boolean isPrimary = itr.quoteInstance.IsSyncing;

            if(quoteId != null && !processedIds.contains(quoteId)){
                Quote q = new Quote(Id = quoteId);
                q.status = 'Cancelled';
                q.RES_Cancellation_Reason__c = cancellationReason;
                q.RES_Unit_Blocked_Start_Date__c = null;
                q.RES_Unit_Blocked_End_Date__c = null;
                recordsToUpdate.add(q);
            }
            if(relatedContractId != null && !processedIds.contains(relatedContractId)){
                Contract c = new Contract(Id = relatedContractId);
                c.Status = 'Canceled';
                recordsToUpdate.add(c);
            }
            if(isPrimary == true && relatedOpportunityId != null && !processedIds.contains(relatedOpportunityId)){
                Opportunity op = new Opportunity(Id = relatedOpportunityId);
                op.StageName = 'Proposal';
                recordsToUpdate.add(op);
            }
        }

        try{
            if(recordsToUpdate.size() > 0){
                Database.update(recordsToUpdate, false, AccessLevel.SYSTEM_MODE);
            }
        }catch(Exception e){
            System.debug('Unknown Exception RES_QuoteCancellationService.cancelQuotation ' + e.getMessage());
        }

        if(quoteIds.size() > 0){
            List<QuoteLineItem> quoteProducts = new RES_QuoteLineItemDAO().getQuoteLineItemsByQuoteIds(quoteIds);
            List<Product2> productToUpdate = new List<Product2>();
            Set<Id> productIds = new Set<Id>();

            for(QuoteLineItem qli: quoteProducts){
                if(productIds.contains(qli.Product2Id)){
                    continue;
                }
                if(qli.Product2Id != null && qli.Product2.RES_Unit_Status__c != 'Available' && qli.Product2.RES_Reserved_By_Quote__c == qli.QuoteId && qli.Product2.RES_Unit_Status__c != 'Sold'){
                    Product2 p = new Product2();
                    p.Id = qli.Product2Id;
                    p.RES_Unit_Status__c = 'Available';
                    p.RES_Is_In_Soft_Hold_Extension__c = false;
                    p.RES_HardBlock_Start__c = null;
                    p.RES_Soft_Hold_Until__c = null;
                    p.RES_Soft_Hold_Start__c = null;
                    p.RES_Reserved_By_Contract__c = null;
                    p.RES_Reserved_By_Quote__c = null;
                    productIds.add(p.Id);
                    productToUpdate.add(p);
                }
            }
            try{
                Database.update(productToUpdate, false, AccessLevel.SYSTEM_MODE);
            }catch(Exception e){
                System.debug('Failed to Update Product to Available ' + e.getMessage());
            }
        }
    }
}