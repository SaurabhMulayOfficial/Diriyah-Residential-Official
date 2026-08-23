/**
 * Class Name   : RES_ProductApprovalController
 * Description  : LWC controller for Product Approval Queue.
 *
 * Framework Rule:
 *      - No SOQL.
 *      - No DML.
 *      - No business logic.
 *      - Delegates to RES_ProductApprovalService.
 *
 * Testability note:
 *      forceExceptionForTests / forcedExceptionMessage below exist ONLY to
 *      let tests exercise the catch/createAuraException() error-handling
 *      path. RES_ProductApprovalService never throws for any legitimate
 *      input (every expected failure is returned as an error message on the
 *      result wrapper instead), so without this seam the catch blocks in
 *      this class would be permanently untestable dead code from a coverage
 *      standpoint. Both fields are @TestVisible (not settable from
 *      production/LWC code) and default to producing no behavior change.
 */
public with sharing class RES_ProductApprovalController {

    @TestVisible
    private static Boolean forceExceptionForTests = false;
    @TestVisible
    private static String forcedExceptionMessage;

    /**
     * Throws a test-only exception when forceExceptionForTests has been
     * set by a test. No-op otherwise. forcedExceptionMessage may be left
     * null to exercise createAuraException()'s blank-message fallback.
     */
    private static void maybeThrowForTest() {
        if (forceExceptionForTests) {
            throw new ForcedTestException(forcedExceptionMessage);
        }
    }

    private class ForcedTestException extends Exception {}

    /**
     * Returns queues accessible to current user.
     */
    @AuraEnabled(cacheable=true)
    public static RES_ProductApprovalService.ApprovalAccessResult getUserApprovalAccess() {
        try {
            maybeThrowForTest();
            return RES_ProductApprovalService.getUserApprovalAccess();
        } catch (Exception ex) {
            throw createAuraException(ex);
        }
    }

    /**
     * Returns Products for selected approval queue.
     */
    @AuraEnabled
    public static RES_ProductApprovalService.ApprovalQueueResult getApprovalQueue(Integer approvalLevel,String searchTerm,Integer pageSize,Datetime lastCreatedDate,Id lastId) {
        try {
            maybeThrowForTest();
            return RES_ProductApprovalService.getApprovalQueue(approvalLevel,searchTerm,pageSize,lastCreatedDate,lastId);
        } catch (Exception ex) {
            throw createAuraException(ex);
        }
    }

    /**
     * Approves selected Products.
     */
    @AuraEnabled
    public static RES_ProductApprovalService.BulkApprovalResult approveProducts(List<Id> productIds) {
        try {
            maybeThrowForTest();
            Set<Id> ids = productIds == null ? new Set<Id>(): new Set<Id>(productIds);
            return RES_ProductApprovalService.approveProducts(ids);
        } catch (Exception ex) {
            throw createAuraException(ex);
        }
    }

    /**
     * Rejects selected Products.
     */
    @AuraEnabled
    public static RES_ProductApprovalService.BulkApprovalResult rejectProducts(List<Id> productIds, String rejectionComment) {
        try {
            maybeThrowForTest();
            Set<Id> ids = productIds == null ? new Set<Id>(): new Set<Id>(productIds);
            return RES_ProductApprovalService.rejectProducts(ids,rejectionComment);
        } catch (Exception ex) {
            throw createAuraException(ex);
        }
    }

    /**
     * Resubmits rejected Products.
     */
    @AuraEnabled
    public static RES_ProductApprovalService.BulkApprovalResult resubmitProducts(List<Id> productIds) {
        try {
            maybeThrowForTest();
            Set<Id> ids = productIds == null ? new Set<Id>(): new Set<Id>(productIds);
            return RES_ProductApprovalService.resubmitProducts(ids);
        } catch (Exception ex) {
            throw createAuraException(ex);
        }
    }

    /**
     * Converts an exception into an LWC-safe exception.
     *
     * NOTE: AuraHandledException.getMessage() always returns the literal
     * string "Script-thrown exception" unless setMessage() is called
     * explicitly after construction - passing the message to the
     * constructor alone is NOT sufficient for it to be retrievable via
     * getMessage() (a well-documented Salesforce platform quirk). Without
     * this explicit setMessage() call, every custom error message this
     * method builds would be silently discarded before ever reaching the
     * LWC's catch block.
     */
    private static AuraHandledException createAuraException(Exception ex) {
        String message = ex != null && !String.isBlank(ex.getMessage()) ? ex.getMessage() : 'An unexpected error occurred.';
        AuraHandledException auraEx = new AuraHandledException(message);
        auraEx.setMessage(message);
        return auraEx;
    }

    /**
     * Returns rejected Products for Operations users.
     */
    @AuraEnabled
    public static RES_ProductApprovalService.ApprovalQueueResult getRejectedProducts(String searchTerm,Integer pageSize,Datetime lastCreatedDate,Id lastId) {
        try {
            maybeThrowForTest();
            return RES_ProductApprovalService.getRejectedProducts(searchTerm,pageSize,lastCreatedDate,lastId);
        } catch (Exception ex) {
            throw createAuraException(ex);
        }
    }
}