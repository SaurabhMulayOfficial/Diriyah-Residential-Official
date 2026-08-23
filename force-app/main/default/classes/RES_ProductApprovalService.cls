/**
 * ==============================================================================
 * Class Name    : RES_ProductApprovalService
 * Description   : Business service for the Product Approval process. Owns all
 *                  business logic, authorization orchestration, state
 *                  validation, and DML for multi-level Product2 approvals.
 *
 * Architecture:
 *
 * Controller
 *      -> Service   (this class: business logic, authorization, state, DML)
 *      -> DAO       (query-only, no business rules)
 *
 * Notes:
 *      - This class performs DML in SYSTEM_MODE (via the DAO layer). Object
 *        and field level security is NOT enforced by the platform here;
 *        access is instead enforced explicitly via
 *        RES_ProductApprovalAuthorization (Custom Permission driven). Any
 *        new field added to the update payloads in this class must be
 *        reviewed for authorization impact.
 *      - All bulk operations (approve/reject/resubmit) support PARTIAL
 *        SUCCESS: a failure on one record never blocks the others.
 *      - Approval/rejection email notifications (via
 *        RES_ProductApprovalNotificationService) are fired ONLY for records
 *        that actually succeeded their DML, and are wrapped in try/catch so
 *        a notification failure can NEVER cause an otherwise-successful
 *        approval/rejection to be reported as failed.
 * ==============================================================================
 */
public without sharing class RES_ProductApprovalService {

    private static final String STATUS_REJECTED = 'Rejected';
    private static final String STATUS_DRAFT = 'Draft';
    private static final Integer DEFAULT_PAGE_SIZE = 50;
    private static final Integer MAX_PAGE_SIZE = 200;
    private static RES_Product2DAOLayer productDAO = new RES_Product2DAOLayer();
    private static RES_ProductApprovalConfigDAOLayer configDAO = new RES_ProductApprovalConfigDAOLayer();

    /*
     * -------------------------------------------------------------------------
     * NOTIFICATION ROUTING (TODO: move to CMDT)
     * -------------------------------------------------------------------------
     *
     * RES_Product_Approval_Config__mdt has no field yet mapping a stage to
     * the Public Group DeveloperName that should be notified when a Product
     * enters/leaves that stage. Until such a field is added, that mapping
     * lives here, keyed by the NEXT status a Product is moving into.
     *
     * Confirmed routing (2026-08-22, verified via Setup > Public Groups):
     *      Draft                    -> Pending Finance Approval -> RES_Finance_Team_Group
     *      Pending Finance Approval -> Pending CSO Approval     -> RES_CSO
     *      Pending CSO Approval     -> (final approval)         -> Operations notification service
     *
     * NOTE: 'RES_Finance_Team' (no _Group suffix) is a Queue's underlying
     * Group record (Type='Queue', used for Order routing), NOT the intended
     * Public Group. Queues and Public Groups both live in the Group table
     * in Salesforce, so a DeveloperName typo here fails silently (zero
     * recipients resolved) rather than throwing - always verify the target
     * is Setup > Public Groups, not Setup > Queues.
     *
     * NOTE: 'POC_Chief_Sales_Officer_Approvals' is a DIFFERENT, separately
     * existing Public Group ("Chief Sales Officer Approvals") - not the
     * "CSO" group (DeveloperName RES_CSO) intended here. Confirmed against
     * Setup > Public Groups screenshots on 2026-08-22.
     */
    private static final Map<String, String> NEXT_STATUS_TO_NOTIFY_GROUP = new Map<String, String>{
        'Pending Finance Approval' => 'RES_Finance_Team_Group',
        'Pending CSO Approval' => 'RES_CSO'
    };

    /**
     * Retrieves active approval configuration.
     *
     * @return List of active RES_Product_Approval_Config__mdt records
     *         (never null; may be empty if none are configured/active).
     */
    private static List<RES_Product_Approval_Config__mdt> getActiveConfigs() {
        return configDAO.getActiveConfigs();
    }

    // ============================================================
    // USER ACCESS
    // ============================================================

    /**
     * Returns the approval queues (and the actions within each) that the
     * current running user is entitled to see/act on.
     *
     * @return ApprovalAccessResult containing the visible steps (sorted by
     *         approval level ascending) and whether the user can view the
     *         Rejected/Operations queue. Never returns null; steps is never
     *         null (may be empty if no active config is visible to the user).
     */
    public static ApprovalAccessResult getUserApprovalAccess() {
        ApprovalAccessResult result = new ApprovalAccessResult();
        result.canViewRejected = RES_ProductApprovalAuthorization.canResubmit();
        List<RES_Product_Approval_Config__mdt> configs = getActiveConfigs();
        if (configs.isEmpty()) {
            return result;
        }

        for (RES_Product_Approval_Config__mdt config : configs) {
            if (config == null || config.RES_Active__c != true) {
                continue;
            }

            if (!RES_ProductApprovalAuthorization.canViewConfig(config)) {
                continue;
            }

            ApprovalStepAccess step = new ApprovalStepAccess();
            step.level = config.RES_Approval_Level__c;
            step.queueLabel = config.RES_Queue_Label__c;
            step.currentStatus = config.RES_Current_Status__c;
            step.canView = true;
            /*
             * CSO visibility does not grant action access.
             */
            step.canApprove = RES_ProductApprovalAuthorization.canApprove(config);
            step.canReject = RES_ProductApprovalAuthorization.canReject(config);
            result.steps.add(step);
        }
        result.steps.sort();
        return result;
    }

    // ============================================================
    // APPROVAL QUEUE
    // ============================================================

    /**
     * Retrieves the Product2 records that are in the queue for the requested
     * approval level, applying an optional search term and keyset pagination.
     *
     * @param approvalLevel   Approval level to fetch the queue for. Required.
     * @param searchTerm      Optional free-text filter (Name/ProductCode/
     *                        Description). NOTE: '%' and '_' typed by the
     *                        user are treated as SOQL LIKE wildcards (not a
     *                        security issue - bind variables prevent
     *                        injection - but can widen matches unexpectedly).
     * @param pageSize        Optional page size; normalized to
     *                        [1, MAX_PAGE_SIZE], defaulting to
     *                        DEFAULT_PAGE_SIZE when null/invalid.
     * @param lastCreatedDate Keyset pagination cursor (CreatedDate of the
     *                        last record from the previous page).
     * @param lastId          Keyset pagination cursor (Id of the last record
     *                        from the previous page).
     * @return ApprovalQueueResult with the page of products, whether more
     *         records exist, and the next pagination cursor. On invalid
     *         level or missing authorization, products is empty and
     *         errorMessage is populated.
     */
    public static ApprovalQueueResult getApprovalQueue(Integer approvalLevel, String searchTerm, Integer pageSize, Datetime lastCreatedDate, Id lastId) {
        ApprovalQueueResult result = new ApprovalQueueResult();
        if (approvalLevel == null) {
            result.errorMessage = System.Label.RES_Product_Invalid_Approval_State;
            return result;
        }

        List<RES_Product_Approval_Config__mdt> configs = getActiveConfigs();
        RES_Product_Approval_Config__mdt config = getConfigByLevel(approvalLevel, configs);
        if (config == null) {
            result.errorMessage = System.Label.RES_Product_Invalid_Approval_State;
            return result;
        }

        /*
         * Server-side authorization.
         */
        if (!RES_ProductApprovalAuthorization.canViewConfig(config)) {
            result.errorMessage = System.Label.RES_Product_Unauthorized_Approval;
            return result;
        }

        List<Product2> products = productDAO.getApprovalQueue(config.RES_Current_Status__c, searchTerm, pageSize, lastCreatedDate, lastId);
        result.products = products;
        Integer safePageSize = normalizePageSize(pageSize);
        result.hasMore = products.size() == safePageSize;
        if (!products.isEmpty()) {
            Product2 lastProduct = products[products.size() - 1];
            result.nextCreatedDate = lastProduct.CreatedDate;
            result.nextId = lastProduct.Id;
        }
        return result;
    }

    // ============================================================
    // APPROVE
    // ============================================================

    /**
     * Approves the given Products, moving each to the next configured
     * status for its current status, provided the running user is
     * authorized for that stage and the record's current state still
     * permits approval.
     *
     * Partial success is supported: each Product is evaluated
     * independently and a failure on one never blocks the others.
     *
     * @param productIds Ids of the Product2 records to approve.
     * @return BulkApprovalResult with per-record success/failure detail.
     *         errorMessage is only set for request-level failures (no ids
     *         supplied, or none of the ids resolve to existing records).
     */
    public static BulkApprovalResult approveProducts(Set<Id> productIds) {
        BulkApprovalResult result = new BulkApprovalResult();
        if (productIds == null || productIds.isEmpty()) {
            result.errorMessage = System.Label.RES_Product_No_Records_Selected;
            return result;
        }

        Set<Id> cleanIds = new Set<Id>(productIds);
        cleanIds.remove(null);
        if (cleanIds.isEmpty()) {
            result.errorMessage = System.Label.RES_Product_No_Records_Selected;
            return result;
        }

        List<Product2> products = productDAO.getProductsByIds(cleanIds);
        if (products.isEmpty()) {
            result.errorMessage = System.Label.RES_Product_Already_Processed;
            return result;
        }

        Map<Id, Product2> productsById = new Map<Id, Product2>(products);

        List<RES_Product_Approval_Config__mdt> configs = getActiveConfigs();
        Map<String, RES_Product_Approval_Config__mdt> configByStatus = RES_ProductApprovalStateService.buildStatusConfigMap(configs);
        List<Product2> recordsToUpdate = new List<Product2>();
        Map<Id, String> nextStatusByProductId = new Map<Id, String>();
        Map<Id, String> currentStatusByProductId = new Map<Id, String>();
        Map<Id, String> validationErrors = new Map<Id, String>();
        Set<Id> foundIds = new Set<Id>();
        for (Product2 product : products) {
            if (product == null || product.Id == null) {
                continue;
            }
            foundIds.add(product.Id);
            String currentStatus = product.RES_Unit_Status__c;
            RES_Product_Approval_Config__mdt config = RES_ProductApprovalStateService.getConfigForStatus(currentStatus, configByStatus);
            if (config == null) {
                validationErrors.put(product.Id, System.Label.RES_Product_Invalid_Approval_State);
                continue;
            }
            /*
             * Authorization is evaluated server-side.
             */
            if (!RES_ProductApprovalAuthorization.canApprove(config)) {
                validationErrors.put(product.Id, System.Label.RES_Product_Unauthorized_Approval);
                continue;
            }

            /*
             * Re-check current Product state.
             *
             * This protects against stale UI/concurrent approval.
             */
            if (!RES_ProductApprovalStateService.canApprove(product, config)) {
                validationErrors.put(product.Id, System.Label.RES_Product_Invalid_Approval_State);
                continue;
            }

            String nextStatus = RES_ProductApprovalStateService.getNextStatus(config);
            if (String.isBlank(nextStatus)) {
                validationErrors.put(product.Id, System.Label.RES_Product_Invalid_Approval_State);
                continue;
            }

            /*
             * Only update the required field.
             */
            Product2 updateProduct = new Product2(Id = product.Id, RES_Unit_Status__c = nextStatus, RES_Rejection_Comment__c = null);
            recordsToUpdate.add(updateProduct);
            nextStatusByProductId.put(product.Id, nextStatus);
            currentStatusByProductId.put(product.Id, currentStatus);
        }

        /*
         * Add validation failures.
         */
        for (Id productId : validationErrors.keySet()) {
            result.failedCount++;
            result.items.add(createFailureResult(productId, validationErrors.get(productId)));
        }

        /*
         * Requested ids that did not resolve to an existing/accessible
         * Product record (e.g. deleted, invalid Id, or filtered out by the
         * DAO's SYSTEM_MODE query) are reported back as failures instead of
         * being silently dropped.
         */
        for (Id requestedId : cleanIds) {
            if (!foundIds.contains(requestedId)) {
                result.failedCount++;
                result.items.add(createFailureResult(requestedId, System.Label.RES_Product_Already_Processed));
            }
        }

        if (recordsToUpdate.isEmpty()) {
            return result;
        }

        /*
         * Partial-success DML.
         */
        Database.SaveResult[] saveResults = Database.update(recordsToUpdate, false, AccessLevel.SYSTEM_MODE);
        List<Id> successfulProductIds = new List<Id>();
        for (Integer index = 0; index < saveResults.size(); index++) {
            Database.SaveResult saveResult = saveResults[index];
            Product2 updateProduct = recordsToUpdate[index];
            if (saveResult.isSuccess()) {
                result.successCount++;
                result.items.add(createSuccessResult(updateProduct.Id, nextStatusByProductId.get(updateProduct.Id)));
                successfulProductIds.add(updateProduct.Id);
            } else {
                result.failedCount++;
                result.items.add(createFailureResult(updateProduct.Id, buildDatabaseErrorMessage(saveResult)));
            }
        }

        /*
         * Fire approval notifications for successfully updated products
         * only. Wrapped defensively so a notification failure can never
         * affect the approval result reported back to the caller.
         */
        try {
            notifyApprovalSuccesses(successfulProductIds, productsById, currentStatusByProductId, configByStatus);
        } catch (Exception notifyEx) {
            System.debug('RES_NOTIFY: approveProducts - notification dispatch threw: ' + notifyEx.getMessage());
        }

        return result;
    }

    // ============================================================
    // REJECT
    // ============================================================

    /**
     * Rejects the given Products, moving each to the Rejected status and
     * recording the supplied rejection comment, provided the running user
     * is authorized for the record's current stage and the record's state
     * still permits rejection.
     *
     * Partial success is supported.
     *
     * @param productIds        Ids of the Product2 records to reject.
     * @param rejectionComment  Mandatory reason for rejection; trimmed
     *                          before persisting.
     * @return BulkApprovalResult with per-record success/failure detail.
     */
    public static BulkApprovalResult rejectProducts(Set<Id> productIds, String rejectionComment) {
        BulkApprovalResult result = new BulkApprovalResult();
        if (productIds == null || productIds.isEmpty()) {
            result.errorMessage = System.Label.RES_Product_No_Records_Selected;
            return result;
        }

        if (String.isBlank(rejectionComment)) {
            result.errorMessage = System.Label.RES_Product_Rejection_Reason_Required;
            return result;
        }
        String cleanComment = rejectionComment.trim();
        Set<Id> cleanIds = new Set<Id>(productIds);
        cleanIds.remove(null);
        if (cleanIds.isEmpty()) {
            result.errorMessage = System.Label.RES_Product_No_Records_Selected;
            return result;
        }

        List<Product2> products = productDAO.getProductsByIds(cleanIds);
        if (products.isEmpty()) {
            result.errorMessage = System.Label.RES_Product_Already_Processed;
            return result;
        }

        Map<Id, Product2> productsById = new Map<Id, Product2>(products);

        List<RES_Product_Approval_Config__mdt> configs = getActiveConfigs();
        Map<String, RES_Product_Approval_Config__mdt> configByStatus = RES_ProductApprovalStateService.buildStatusConfigMap(configs);
        List<Product2> recordsToUpdate = new List<Product2>();
        Map<Id, String> currentStatusByProductId = new Map<Id, String>();
        Set<Id> foundIds = new Set<Id>();
        for (Product2 product : products) {
            if (product == null || product.Id == null) {
                continue;
            }
            foundIds.add(product.Id);
            String currentStatus = product.RES_Unit_Status__c;
            RES_Product_Approval_Config__mdt config = configByStatus.get(currentStatus);
            if (config == null) {
                result.failedCount++;
                result.items.add(createFailureResult(product.Id, System.Label.RES_Product_Invalid_Approval_State));
                continue;
            }

            /*
             * Only the configured approver can reject
             * that particular stage.
             */
            if (!RES_ProductApprovalAuthorization.canReject(config)) {
                result.failedCount++;
                result.items.add(createFailureResult(product.Id, System.Label.RES_Product_Unauthorized_Approval));
                continue;
            }

            if (!RES_ProductApprovalStateService.canReject(currentStatus)) {
                result.failedCount++;
                result.items.add(createFailureResult(product.Id, System.Label.RES_Product_Invalid_Approval_State));
                continue;
            }

            Product2 updateProduct = new Product2(Id = product.Id, RES_Unit_Status__c = STATUS_REJECTED, RES_Rejection_Comment__c = cleanComment);
            recordsToUpdate.add(updateProduct);
            currentStatusByProductId.put(product.Id, currentStatus);
        }

        for (Id requestedId : cleanIds) {
            if (!foundIds.contains(requestedId)) {
                result.failedCount++;
                result.items.add(createFailureResult(requestedId, System.Label.RES_Product_Already_Processed));
            }
        }

        if (recordsToUpdate.isEmpty()) {
            return result;
        }

        Database.SaveResult[] saveResults = Database.update(recordsToUpdate, false, AccessLevel.SYSTEM_MODE);
        List<Id> successfulProductIds = new List<Id>();
        for (Integer index = 0; index < saveResults.size(); index++) {
            Database.SaveResult saveResult = saveResults[index];
            Product2 updateProduct = recordsToUpdate[index];
            if (saveResult.isSuccess()) {
                result.successCount++;
                result.items.add(createSuccessResult(updateProduct.Id, STATUS_REJECTED));
                successfulProductIds.add(updateProduct.Id);
            } else {
                result.failedCount++;
                result.items.add(createFailureResult(updateProduct.Id, buildDatabaseErrorMessage(saveResult)));
            }
        }

        /*
         * Fire rejection notifications for successfully rejected products
         * only. Wrapped defensively so a notification failure can never
         * affect the rejection result reported back to the caller.
         */
        try {
            notifyRejectionSuccesses(successfulProductIds, productsById, currentStatusByProductId, configByStatus, cleanComment);
        } catch (Exception notifyEx) {
            System.debug('RES_NOTIFY: rejectProducts - notification dispatch threw: ' + notifyEx.getMessage());
        }

        return result;
    }

    // ============================================================
    // RESUBMIT
    // ============================================================

    /**
     * Moves the given Products from Rejected back to Draft, clearing the
     * rejection comment. Restricted to users with Operations resubmit
     * access (see RES_ProductApprovalAuthorization.canResubmit()).
     *
     * @param productIds Ids of the Product2 records to resubmit.
     * @return BulkApprovalResult with per-record success/failure detail.
     *         errorMessage is set if no ids were supplied or the running
     *         user lacks resubmit access.
     */
    public static BulkApprovalResult resubmitProducts(Set<Id> productIds) {
        BulkApprovalResult result = new BulkApprovalResult();
        if (productIds == null || productIds.isEmpty()) {
            result.errorMessage = System.Label.RES_Product_No_Records_Selected;
            return result;
        }

        if (!RES_ProductApprovalAuthorization.canResubmit()) {
            result.errorMessage = System.Label.RES_Product_Unauthorized_Approval;
            return result;
        }
        Set<Id> cleanIds = new Set<Id>(productIds);
        cleanIds.remove(null);
        if (cleanIds.isEmpty()) {
            result.errorMessage = System.Label.RES_Product_No_Records_Selected;
            return result;
        }
        List<Product2> products = productDAO.getProductsByIds(cleanIds);
        List<Product2> recordsToUpdate = new List<Product2>();
        Set<Id> foundIds = new Set<Id>();

        for (Product2 product : products) {
            if (product == null || product.Id == null) {
                continue;
            }
            foundIds.add(product.Id);
            if (!RES_ProductApprovalStateService.canResubmit(product.RES_Unit_Status__c)) {
                result.failedCount++;
                result.items.add(createFailureResult(product.Id, System.Label.RES_Product_Invalid_Approval_State));
                continue;
            }
            Product2 updateProduct = new Product2(
                Id = product.Id,
                RES_Unit_Status__c = STATUS_DRAFT,
                RES_Rejection_Comment__c = null
            );
            recordsToUpdate.add(updateProduct);
        }

        for (Id requestedId : cleanIds) {
            if (!foundIds.contains(requestedId)) {
                result.failedCount++;
                result.items.add(createFailureResult(requestedId, System.Label.RES_Product_Already_Processed));
            }
        }

        if (recordsToUpdate.isEmpty()) {
            return result;
        }

        Database.SaveResult[] saveResults = Database.update(recordsToUpdate, false, AccessLevel.SYSTEM_MODE);
        for (Integer index = 0; index < saveResults.size(); index++) {
            Database.SaveResult saveResult = saveResults[index];
            Product2 product = recordsToUpdate[index];
            if (saveResult.isSuccess()) {
                result.successCount++;
                result.items.add(createSuccessResult(product.Id, STATUS_DRAFT));
            } else {
                result.failedCount++;
                result.items.add(createFailureResult(product.Id, buildDatabaseErrorMessage(saveResult)));
            }
        }
        return result;
    }

    // ============================================================
    // PRIVATE HELPERS
    // ============================================================

    /**
     * Groups successfully-approved products by their originating status and
     * fires one RES_ProductApprovalNotificationService.notifyNextApprovalTeam()
     * call per group - either to the next stage's group (looked up via
     * NEXT_STATUS_TO_NOTIFY_GROUP), or via notifyFinalApproval() when the
     * originating config is the final approval level.
     *
     * @param successfulProductIds  Ids that succeeded their status-update DML.
     * @param productsById          Full Product2 records (Name/ProductCode
     *                              etc.) keyed by Id, for email content.
     * @param currentStatusByProductId Each product's status BEFORE approval.
     * @param configByStatus        Active configs keyed by RES_Current_Status__c.
     */
    private static void notifyApprovalSuccesses(
        List<Id> successfulProductIds,
        Map<Id, Product2> productsById,
        Map<Id, String> currentStatusByProductId,
        Map<String, RES_Product_Approval_Config__mdt> configByStatus
    ) {
        if (successfulProductIds == null || successfulProductIds.isEmpty()) {
            return;
        }

        Map<String, List<Product2>> successesByCurrentStatus = new Map<String, List<Product2>>();
        for (Id productId : successfulProductIds) {
            String currentStatus = currentStatusByProductId.get(productId);
            Product2 fullProduct = productsById.get(productId);
            if (String.isBlank(currentStatus) || fullProduct == null) {
                continue;
            }
            if (!successesByCurrentStatus.containsKey(currentStatus)) {
                successesByCurrentStatus.put(currentStatus, new List<Product2>());
            }
            successesByCurrentStatus.get(currentStatus).add(fullProduct);
        }

        for (String currentStatus : successesByCurrentStatus.keySet()) {
            RES_Product_Approval_Config__mdt config = configByStatus.get(currentStatus);
            if (config == null) {
                continue;
            }

            List<Product2> groupProducts = successesByCurrentStatus.get(currentStatus);
            String currentTeamLabel = config.RES_Queue_Label__c;
            String nextStatus = RES_ProductApprovalStateService.getNextStatus(config);

            if (RES_ProductApprovalStateService.isFinalApproval(config)) {
                RES_ProductApprovalNotificationService.notifyFinalApproval(groupProducts, currentTeamLabel);
                continue;
            }

            String nextTeamGroupDeveloperName = NEXT_STATUS_TO_NOTIFY_GROUP.get(nextStatus);
            if (String.isBlank(nextTeamGroupDeveloperName)) {
                System.debug('RES_NOTIFY: notifyApprovalSuccesses - no Public Group mapped for next status "' + nextStatus + '". Add it to NEXT_STATUS_TO_NOTIFY_GROUP.');
                continue;
            }

            RES_Product_Approval_Config__mdt nextConfig = configByStatus.get(nextStatus);
            String nextTeamLabel = nextConfig != null ? nextConfig.RES_Queue_Label__c : nextStatus;

            RES_ProductApprovalNotificationService.notifyNextApprovalTeam(
                groupProducts,
                currentTeamLabel,
                nextTeamLabel,
                nextTeamGroupDeveloperName
            );
        }
    }

    /**
     * Groups successfully-rejected products by their originating status and
     * fires one RES_ProductApprovalNotificationService.notifyProductRejection()
     * call per group, so the rejecting team's label is correct even if a
     * single bulk rejection spans multiple stages.
     *
     * @param successfulProductIds     Ids that succeeded the reject DML.
     * @param productsById             Full Product2 records keyed by Id.
     * @param currentStatusByProductId Each product's status BEFORE rejection.
     * @param configByStatus           Active configs keyed by RES_Current_Status__c.
     * @param rejectionComment         Trimmed rejection reason to include in the email.
     */
    private static void notifyRejectionSuccesses(
        List<Id> successfulProductIds,
        Map<Id, Product2> productsById,
        Map<Id, String> currentStatusByProductId,
        Map<String, RES_Product_Approval_Config__mdt> configByStatus,
        String rejectionComment
    ) {
        if (successfulProductIds == null || successfulProductIds.isEmpty()) {
            return;
        }

        Map<String, List<Product2>> rejectionsByCurrentStatus = new Map<String, List<Product2>>();
        for (Id productId : successfulProductIds) {
            String currentStatus = currentStatusByProductId.get(productId);
            Product2 fullProduct = productsById.get(productId);
            if (String.isBlank(currentStatus) || fullProduct == null) {
                continue;
            }
            if (!rejectionsByCurrentStatus.containsKey(currentStatus)) {
                rejectionsByCurrentStatus.put(currentStatus, new List<Product2>());
            }
            rejectionsByCurrentStatus.get(currentStatus).add(fullProduct);
        }

        for (String currentStatus : rejectionsByCurrentStatus.keySet()) {
            RES_Product_Approval_Config__mdt config = configByStatus.get(currentStatus);
            String rejectingTeamLabel = config != null ? config.RES_Queue_Label__c : currentStatus;

            RES_ProductApprovalNotificationService.notifyProductRejection(
                rejectionsByCurrentStatus.get(currentStatus),
                rejectingTeamLabel,
                rejectionComment
            );
        }
    }

    /**
     * Finds the active approval configuration matching a given approval
     * level.
     *
     * @param approvalLevel Level to match.
     * @param configs       Candidate configurations to search.
     * @return Matching configuration, or null if approvalLevel/configs is
     *         null, or no configuration has RES_Approval_Level__c equal to
     *         approvalLevel.
     */
    private static RES_Product_Approval_Config__mdt getConfigByLevel(Integer approvalLevel, List<RES_Product_Approval_Config__mdt> configs) {
        if (approvalLevel == null || configs == null) {
            return null;
        }

        for (RES_Product_Approval_Config__mdt config : configs) {
            /*
             * NOTE: intValue() is used instead of a String round-trip
             * (Integer.valueOf(String.valueOf(...))) because the latter
             * throws a NumberFormatException if RES_Approval_Level__c ever
             * holds a decimal value (e.g. 1.5). intValue() truncates safely
             * and never throws for a non-null Decimal.
             */
            if (config != null && config.RES_Approval_Level__c != null && config.RES_Approval_Level__c.intValue() == approvalLevel) {
                return config;
            }
        }
        return null;
    }

    /**
     * Clamps a requested page size to the supported range, applying the
     * default when the request is missing or invalid.
     *
     * @param requestedPageSize Page size requested by the caller.
     * @return A value in [1, MAX_PAGE_SIZE]; DEFAULT_PAGE_SIZE when
     *         requestedPageSize is null or <= 0.
     */
    private static Integer normalizePageSize(Integer requestedPageSize) {
        if (requestedPageSize == null || requestedPageSize <= 0) {
            return DEFAULT_PAGE_SIZE;
        }
        return Math.min(requestedPageSize, MAX_PAGE_SIZE);
    }

    /**
     * Builds a human-readable error message from a failed Database.SaveResult.
     *
     * @param saveResult Failed save result.
     * @return Concatenated error messages (joined by "; "), or a generic
     *         fallback message if saveResult/errors are null or empty.
     */
    private static String buildDatabaseErrorMessage(Database.SaveResult saveResult) {
        if (saveResult == null || saveResult.getErrors() == null || saveResult.getErrors().isEmpty()) {
            return 'Product update failed.';
        }

        List<String> messages = new List<String>();
        for (Database.Error error : saveResult.getErrors()) {
            if (error != null && !String.isBlank(error.getMessage())) {
                messages.add(error.getMessage());
            }
        }

        return messages.isEmpty() ? 'Product update failed.' : String.join(messages, '; ');
    }

    /**
     * Builds a successful ApprovalItemResult.
     *
     * @param productId Id of the affected Product2 record.
     * @param newStatus Status the record was moved to.
     * @return Populated ApprovalItemResult with success = true.
     */
    private static ApprovalItemResult createSuccessResult(Id productId, String newStatus) {
        ApprovalItemResult item = new ApprovalItemResult();
        item.productId = productId;
        item.success = true;
        item.newStatus = newStatus;
        return item;
    }

    /**
     * Builds a failed ApprovalItemResult.
     *
     * @param productId    Id of the affected Product2 record (or requested
     *                     id, if the record could not be resolved).
     * @param errorMessage Reason for the failure.
     * @return Populated ApprovalItemResult with success = false.
     */
    private static ApprovalItemResult createFailureResult(Id productId, String errorMessage) {
        ApprovalItemResult item = new ApprovalItemResult();
        item.productId = productId;
        item.success = false;
        item.errorMessage = errorMessage;
        return item;
    }

    /**
     * Retrieves rejected Products for Operations users.
     *
     * Server-side authorization is mandatory.
     *
     * @param searchTerm      Optional free-text filter.
     * @param pageSize        Optional page size (normalized as per
     *                        normalizePageSize()).
     * @param lastCreatedDate Keyset pagination cursor.
     * @param lastId          Keyset pagination cursor.
     * @return ApprovalQueueResult with the page of rejected products. If the
     *         running user lacks resubmit access, products is empty and
     *         errorMessage is populated.
     */
    public static ApprovalQueueResult getRejectedProducts(String searchTerm, Integer pageSize, Datetime lastCreatedDate, Id lastId) {
        ApprovalQueueResult result = new ApprovalQueueResult();
        if (!RES_ProductApprovalAuthorization.canResubmit()) {
            result.errorMessage = System.Label.RES_Product_Unauthorized_Approval;
            return result;
        }

        List<Product2> products = productDAO.getRejectedProducts(STATUS_REJECTED, searchTerm, pageSize, lastCreatedDate, lastId);
        result.products = products;
        Integer safePageSize = normalizePageSize(pageSize);
        result.hasMore = products.size() == safePageSize;
        if (!products.isEmpty()) {
            Product2 lastProduct = products[products.size() - 1];
            result.nextCreatedDate = lastProduct.CreatedDate;
            result.nextId = lastProduct.Id;
        }
        return result;
    }

    // ============================================================
    // WRAPPERS
    // ============================================================

    /**
     * Wrapper describing the approval queues/actions visible to the
     * current user.
     */
    public class ApprovalAccessResult {
        @AuraEnabled
        public List<ApprovalStepAccess> steps = new List<ApprovalStepAccess>();
        @AuraEnabled
        public Boolean canViewRejected = false;
    }

    /**
     * Wrapper describing a single approval level's visibility/action
     * access for the current user. Sortable by level ascending.
     */
    public class ApprovalStepAccess implements Comparable {
        @AuraEnabled
        public Decimal level;
        @AuraEnabled
        public String queueLabel;
        @AuraEnabled
        public String currentStatus;
        @AuraEnabled
        public Boolean canView = false;
        @AuraEnabled
        public Boolean canApprove = false;
        @AuraEnabled
        public Boolean canReject = false;

        /**
         * Compares by level ascending. Null-safe: a null level (which
         * should not occur for a properly configured metadata record) is
         * treated as less than any non-null level rather than throwing.
         *
         * @param obj Other ApprovalStepAccess to compare against.
         * @return -1/0/1, or 1 if obj is null/not comparable.
         */
        public Integer compareTo(Object obj) {
            ApprovalStepAccess other = (ApprovalStepAccess) obj;
            if (other == null) {
                return 1;
            }
            if (level == other.level) {
                return 0;
            }
            if (level == null) {
                return -1;
            }
            if (other.level == null) {
                return 1;
            }
            return level < other.level ? -1 : 1;
        }
    }

    /**
     * Wrapper for a page of approval queue results.
     */
    public class ApprovalQueueResult {
        @AuraEnabled
        public List<Product2> products = new List<Product2>();
        @AuraEnabled
        public Boolean hasMore = false;
        @AuraEnabled
        public Datetime nextCreatedDate;
        @AuraEnabled
        public Id nextId;
        @AuraEnabled
        public String errorMessage;
    }

    /**
     * Wrapper for the outcome of a bulk approve/reject/resubmit operation.
     */
    public class BulkApprovalResult {
        @AuraEnabled
        public Integer successCount = 0;
        @AuraEnabled
        public Integer failedCount = 0;
        @AuraEnabled
        public String errorMessage;
        @AuraEnabled
        public List<ApprovalItemResult> items = new List<ApprovalItemResult>();
    }

    /**
     * Wrapper for a single record's outcome within a bulk operation.
     */
    public class ApprovalItemResult {
        @AuraEnabled
        public Id productId;
        @AuraEnabled
        public Boolean success;
        @AuraEnabled
        public String newStatus;
        @AuraEnabled
        public String errorMessage;
    }
}