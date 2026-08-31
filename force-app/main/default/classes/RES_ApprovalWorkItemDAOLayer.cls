/**
 * Class Name   : RES_ApprovalWorkItemDAOLayer
 * Description  : Data Access Object (DAO) layer for the ApprovalWorkItem object.
 *                Provides standardized methods for querying and retrieving
 *                ApprovalWorkItem records within the application.
 *
 * Framework Rule:
 *      - All DAO layers must extend RES_BaseDAOLayer.
 *      - Each implementation must override getSObjectName()
 *        to specify the associated SObject.
 */
public with sharing class RES_ApprovalWorkItemDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ApprovalWorkItem';
    }

    /**
     * DIR-869: Aggregate count of Rejected discount-approval work items per Quote,
     * used by RES_QuoteApprovalWorkItemService to detect the 3+ rejections escalation
     * scenario. Dynamic (useCache = false) since Status changes on every decision.
     */
    public List<AggregateResult> getRejectionCountsByQuoteIds(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return new List<AggregateResult>();
        }
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('quoteIds', quoteIds);

        String soql = 'SELECT RelatedRecordId quoteId, COUNT(Id) rejectionCount ' +
                      'FROM ApprovalWorkItem ' +
                      'WHERE RelatedRecordId IN :quoteIds ' +
                      'AND RelatedRecordObjectName = \'Quote\' ' +
                      'AND Status = \'Rejected\' ' +
                      'GROUP BY RelatedRecordId';
        return (List<AggregateResult>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}