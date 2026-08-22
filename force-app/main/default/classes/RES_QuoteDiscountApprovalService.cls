/**
 * Business logic for Quote Discount approval orchestration.
 */
public with sharing class RES_QuoteDiscountApprovalService {
    /**
     * Returns prior rejected discount attempts by Quote, defaulting missing
     * Quotes to zero so Flow receives a deterministic result per request.
     */
    public static Map<Id, Integer> getPriorRejectionCounts(Set<Id> quoteIds) {
        Map<Id, Integer> countsByQuoteId = new Map<Id, Integer>();
        if (quoteIds == null || quoteIds.isEmpty()) {
            return countsByQuoteId;
        }

        countsByQuoteId.putAll(
            new RES_DiscountAuditLogDAO().getRejectedDiscountAttemptCounts(quoteIds)
        );
        for (Id quoteId : quoteIds) {
            if (!countsByQuoteId.containsKey(quoteId)) {
                countsByQuoteId.put(quoteId, 0);
            }
        }
        return countsByQuoteId;
    }

    @InvocableMethod(label='Get Quote Discount Rejection Count')
    public static List<Output> getRejectionCounts(List<Input> inputs) {
        Set<Id> quoteIds = new Set<Id>();
        for (Input input : inputs) {
            if (input != null && input.quoteId != null) {
                quoteIds.add(input.quoteId);
            }
        }

        Map<Id, Integer> countsByQuoteId = getPriorRejectionCounts(quoteIds);
        List<Output> outputs = new List<Output>();
        for (Input input : inputs) {
            Output output = new Output();
            output.rejectionCount = input == null || input.quoteId == null
                ? 0
                : countsByQuoteId.get(input.quoteId);
            if (output.rejectionCount == null) {
                output.rejectionCount = 0;
            }
            outputs.add(output);
        }
        return outputs;
    }

    public class Input {
        @InvocableVariable(required=true)
        public Id quoteId;
    }

    public class Output {
        @InvocableVariable
        public Integer rejectionCount;
    }

}
