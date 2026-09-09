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
 */
public with sharing class RES_ProductApprovalController {

    @TestVisible
    private static Boolean forceExceptionForTests = false;
    @TestVisible
    private static String forcedExceptionMessage;

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

    /**
     * Submits Draft or Rejected Products for approval (Operations -> DevCo).
     */
    @AuraEnabled
    public static RES_ProductApprovalService.BulkApprovalResult submitForApproval(List<Id> productIds) {
        try {
            maybeThrowForTest();
            Set<Id> ids = productIds == null ? new Set<Id>() : new Set<Id>(productIds);
            return RES_ProductApprovalService.submitForApproval(ids);
        } catch (Exception ex) {
            throw createAuraException(ex);
        }
    }
}