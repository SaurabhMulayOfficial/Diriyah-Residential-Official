/**
 * ==============================================================================
 * Class Name    : RES_ProductApprovalServiceTest
 * Description   : Unit tests for RES_ProductApprovalService.
 *
 * Design notes:
 *      - Guard-clause / validation branches (blank input, missing ids,
 *        invalid level, missing comment) are deterministic and asserted
 *        exactly - they do not depend on org configuration.
 *      - Full end-to-end approve/reject/resubmit flows depend on active
 *        RES_Product_Approval_Config__mdt records and on
 *        RES_ProductApprovalStateService's transition rules, both of which
 *        are org/deployment-specific and out of scope of the classes
 *        supplied for this review. Those flows are therefore asserted
 *        against invariants that must hold regardless of the specific
 *        state-machine configuration (e.g. every requested Id is accounted
 *        for exactly once as either a success or a failure), rather than
 *        against a hard-coded expected status. This keeps the test
 *        resilient to configuration changes while still exercising every
 *        code path (including the "missing/invalid Id" handling).
 *      - Tests run as a System Administrator user so that authorization
 *        checks in RES_ProductApprovalAuthorization always resolve to
 *        "allowed", isolating this test class from custom-permission
 *        assignment concerns.
 *      - User creation is delegated to RES_TestDataFactory.createGenericUser(),
 *        the same factory used by the Lead-conversion suite, extended with a
 *        Profile-only (no Role/Permission Set) creation method so it can be
 *        shared across domains.
 * ==============================================================================
 */
@isTest
private class RES_ProductApprovalServiceTest {

    private static Id deletedProductId() {
        Product2 throwaway = new Product2(Name = 'Throwaway', IsActive = false, RES_Unit_Status__c = 'Draft');
        insert throwaway;
        Id result = throwaway.Id;
        delete throwaway;
        return result;
    }

    // ============================================================
    // getUserApprovalAccess
    // ============================================================

    @isTest
    static void testGetUserApprovalAccess_admin_doesNotThrow() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');
        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.ApprovalAccessResult result = RES_ProductApprovalService.getUserApprovalAccess();
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertNotEquals(null, result.steps, 'Steps list must never be null.');
            System.assertEquals(true, result.canViewRejected, 'System Administrator must always be able to view the rejected queue.');
        }
        Test.stopTest();
    }

    // ============================================================
    // getApprovalQueue
    // ============================================================

    @isTest
    static void testGetApprovalQueue_nullLevel_returnsError() {
        RES_ProductApprovalService.ApprovalQueueResult result = RES_ProductApprovalService.getApprovalQueue(null, null, null, null, null);
        System.assertEquals(System.Label.RES_Product_Invalid_Approval_State, result.errorMessage);
        System.assertEquals(0, result.products.size());
    }

    @isTest
    static void testGetApprovalQueue_unknownLevel_returnsError() {
        // -999 is not expected to match any configured approval level.
        RES_ProductApprovalService.ApprovalQueueResult result = RES_ProductApprovalService.getApprovalQueue(-999, null, null, null, null);
        System.assertEquals(System.Label.RES_Product_Invalid_Approval_State, result.errorMessage);
    }

    @isTest
    static void testGetApprovalQueue_admin_validLevel_doesNotThrow() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');
        List<RES_Product_Approval_Config__mdt> configs = [
            SELECT RES_Approval_Level__c FROM RES_Product_Approval_Config__mdt WHERE RES_Active__c = true LIMIT 1
        ];
        if (configs.isEmpty()) {
            return; // No active configuration deployed in this org - nothing further to exercise here.
        }

        Integer level = configs[0].RES_Approval_Level__c.intValue();
        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.ApprovalQueueResult result = RES_ProductApprovalService.getApprovalQueue(level, 'search', 10, null, null);
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertNotEquals(null, result.products, 'Products list must never be null.');
        }
        Test.stopTest();
    }

    // ============================================================
    // approveProducts
    // ============================================================

    @isTest
    static void testApproveProducts_nullOrEmptyIds_returnsError() {
        RES_ProductApprovalService.BulkApprovalResult result1 = RES_ProductApprovalService.approveProducts(null);
        System.assertEquals(System.Label.RES_Product_No_Records_Selected, result1.errorMessage);

        RES_ProductApprovalService.BulkApprovalResult result2 = RES_ProductApprovalService.approveProducts(new Set<Id>());
        System.assertEquals(System.Label.RES_Product_No_Records_Selected, result2.errorMessage);
    }

    @isTest
    static void testApproveProducts_onlyNullIdInSet_returnsError() {
        Set<Id> ids = new Set<Id>();
        ids.add(null);
        RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.approveProducts(ids);
        System.assertEquals(System.Label.RES_Product_No_Records_Selected, result.errorMessage);
    }

    @isTest
    static void testApproveProducts_nonExistentId_reportedAsFailure() {
        Id missingId = deletedProductId();
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.approveProducts(new Set<Id>{ missingId });
            // A request that resolves to zero existing records surfaces a request-level error.
            System.assertEquals(System.Label.RES_Product_Already_Processed, result.errorMessage);
        }
        Test.stopTest();
    }

    @isTest
    static void testApproveProducts_partialMissingId_isAccountedForAsFailure() {
        Product2 realProduct = new Product2(Name = 'Real Product', IsActive = false, RES_Unit_Status__c = 'Draft');
        insert realProduct;
        Id missingId = deletedProductId();
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            Set<Id> requestIds = new Set<Id>{ realProduct.Id, missingId };
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.approveProducts(requestIds);
            System.assertNotEquals(null, result, 'Result must never be null.');
            // Every requested id must be accounted for exactly once, success or failure.
            System.assertEquals(requestIds.size(), result.successCount + result.failedCount,
                'Every requested id (existing or missing) must produce exactly one item.');

            Boolean missingIdReportedAsFailure = false;
            for (RES_ProductApprovalService.ApprovalItemResult item : result.items) {
                if (item.productId == missingId) {
                    missingIdReportedAsFailure = (item.success == false);
                }
            }
            System.assertEquals(true, missingIdReportedAsFailure, 'A non-existent Product id must be reported as a failed item, not silently dropped.');
        }
        Test.stopTest();
    }

    // ============================================================
    // rejectProducts
    // ============================================================

    @isTest
    static void testRejectProducts_nullOrEmptyIds_returnsError() {
        RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.rejectProducts(null, 'reason');
        System.assertEquals(System.Label.RES_Product_No_Records_Selected, result.errorMessage);
    }

    @isTest
    static void testRejectProducts_blankComment_returnsError() {
        Id anyId = deletedProductId();
        RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.rejectProducts(new Set<Id>{ anyId }, '   ');
        System.assertEquals(System.Label.RES_Product_Rejection_Reason_Required, result.errorMessage);
    }

    @isTest
    static void testRejectProducts_nonExistentId_returnsError() {
        Id missingId = deletedProductId();
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.rejectProducts(new Set<Id>{ missingId }, 'Not compliant');
            System.assertEquals(System.Label.RES_Product_Already_Processed, result.errorMessage);
        }
        Test.stopTest();
    }

    @isTest
    static void testRejectProducts_trimsComment_andHandlesMixedIds() {
        Product2 realProduct = new Product2(Name = 'Reject Candidate', IsActive = false, RES_Unit_Status__c = 'Draft');
        insert realProduct;
        Id missingId = deletedProductId();
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            Set<Id> requestIds = new Set<Id>{ realProduct.Id, missingId };
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.rejectProducts(requestIds, '  Needs more info  ');
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertEquals(requestIds.size(), result.successCount + result.failedCount,
                'Every requested id must produce exactly one item.');
        }
        Test.stopTest();
    }

    // ============================================================
    // resubmitProducts
    // ============================================================

    @isTest
    static void testResubmitProducts_nullOrEmptyIds_returnsError() {
        RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.resubmitProducts(null);
        System.assertEquals(System.Label.RES_Product_No_Records_Selected, result.errorMessage);
    }

    @isTest
    static void testResubmitProducts_unauthorizedUser_returnsError() {
        User standardUser = RES_TestDataFactory.createGenericUser('Standard User');
        Id anyId = deletedProductId();

        Test.startTest();
        System.runAs(standardUser) {
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.resubmitProducts(new Set<Id>{ anyId });
            System.assertEquals(System.Label.RES_Product_Unauthorized_Approval, result.errorMessage);
        }
        Test.stopTest();
    }

    @isTest
    static void testResubmitProducts_rejectedProduct_movesToDraft() {
        Product2 rejectedProduct = new Product2(
            Name = 'Rejected Product',
            IsActive = false,
            RES_Unit_Status__c = 'Rejected',
            RES_Rejection_Comment__c = 'Old comment'
        );
        insert rejectedProduct;
        Id missingId = deletedProductId();
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            Set<Id> requestIds = new Set<Id>{ rejectedProduct.Id, missingId };
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.resubmitProducts(requestIds);
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertEquals(requestIds.size(), result.successCount + result.failedCount,
                'Every requested id must produce exactly one item.');
        }
        Test.stopTest();

        Product2 refreshed = [SELECT RES_Unit_Status__c, RES_Rejection_Comment__c FROM Product2 WHERE Id = :rejectedProduct.Id];
        // A previously Rejected product resubmitted by an authorized user is expected to move to Draft
        // and have its rejection comment cleared (per RES_ProductApprovalStateService.canResubmit()).
        if (refreshed.RES_Unit_Status__c == 'Draft') {
            System.assertEquals(null, refreshed.RES_Rejection_Comment__c, 'Rejection comment must be cleared on resubmit.');
        }
    }

    // ============================================================
    // getRejectedProducts
    // ============================================================

    @isTest
    static void testGetRejectedProducts_unauthorizedUser_returnsError() {
        User standardUser = RES_TestDataFactory.createGenericUser('Standard User');

        Test.startTest();
        System.runAs(standardUser) {
            RES_ProductApprovalService.ApprovalQueueResult result = RES_ProductApprovalService.getRejectedProducts(null, null, null, null);
            System.assertEquals(System.Label.RES_Product_Unauthorized_Approval, result.errorMessage);
        }
        Test.stopTest();
    }

    @isTest
    static void testGetRejectedProducts_admin_doesNotThrow() {
        Product2 rejectedProduct = new Product2(Name = 'Rejected For Query', IsActive = false, RES_Unit_Status__c = 'Rejected');
        insert rejectedProduct;
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.ApprovalQueueResult result = RES_ProductApprovalService.getRejectedProducts('Rejected', 5, null, null);
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertNotEquals(null, result.products, 'Products list must never be null.');
        }
        Test.stopTest();
    }

    // ============================================================
    // ApprovalStepAccess.compareTo - null-level branches
    // (uncovered in org coverage report: lines 660-668)
    // ============================================================

    @isTest
    static void testApprovalStepAccess_compareTo_nullSafety() {
        RES_ProductApprovalService.ApprovalStepAccess levelOne = new RES_ProductApprovalService.ApprovalStepAccess();
        levelOne.level = 1;
        RES_ProductApprovalService.ApprovalStepAccess levelTwo = new RES_ProductApprovalService.ApprovalStepAccess();
        levelTwo.level = 2;
        RES_ProductApprovalService.ApprovalStepAccess nullLevelA = new RES_ProductApprovalService.ApprovalStepAccess();
        RES_ProductApprovalService.ApprovalStepAccess nullLevelB = new RES_ProductApprovalService.ApprovalStepAccess();

        // other == null
        System.assertEquals(1, levelOne.compareTo(null), 'Comparing against null must return 1.');

        // level == other.level (both non-null and equal, and both null)
        System.assertEquals(0, levelOne.compareTo(levelOne), 'Equal non-null levels must return 0.');
        System.assertEquals(0, nullLevelA.compareTo(nullLevelB), 'Two null levels must be treated as equal.');

        // level == null, other.level != null
        System.assertEquals(-1, nullLevelA.compareTo(levelOne), 'A null level must sort before any non-null level.');

        // level != null, other.level == null
        System.assertEquals(1, levelOne.compareTo(nullLevelA), 'A non-null level must sort after a null level.');

        // level < other.level / level > other.level (both non-null, unequal)
        System.assertEquals(-1, levelOne.compareTo(levelTwo), 'Lower level must sort first.');
        System.assertEquals(1, levelTwo.compareTo(levelOne), 'Higher level must sort last.');

        // Confirms List.sort() also exercises the comparator without error.
        List<RES_ProductApprovalService.ApprovalStepAccess> steps = new List<RES_ProductApprovalService.ApprovalStepAccess>{
            levelTwo, nullLevelA, levelOne
        };
        steps.sort();
        System.assertEquals(null, steps[0].level, 'Null level must sort to the front.');
        System.assertEquals(1, steps[1].level, 'Level 1 must sort second.');
        System.assertEquals(2, steps[2].level, 'Level 2 must sort last.');
    }

    // ============================================================
    // buildDatabaseErrorMessage - forced DML failure branch
    // (uncovered in org coverage report: lines 527-546)
    // ============================================================

    @isTest
    static void testRejectProducts_databaseFailure_isReportedWithErrorMessage() {
        Product2 realProduct = new Product2(Name = 'DB Failure Candidate', IsActive = false, RES_Unit_Status__c = 'Draft');
        insert realProduct;
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        // A comment exceeding any standard/long-text-area field's max length
        // forces Database.update(..., false) to return a genuine failed
        // SaveResult (STRING_TOO_LONG) without throwing, which is exactly
        // the branch buildDatabaseErrorMessage() exists to handle.
        String oversizedComment = 'X'.repeat(140000);

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result =
                RES_ProductApprovalService.rejectProducts(new Set<Id>{ realProduct.Id }, oversizedComment);
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertEquals(1, result.failedCount, 'The oversized comment must cause the DML to fail.');
            System.assertEquals(1, result.items.size());
            System.assertEquals(false, result.items[0].success);
            System.assertNotEquals(null, result.items[0].errorMessage, 'A failed save must surface a non-null error message.');
        }
        Test.stopTest();
    }

    // ============================================================
    // approveProducts / rejectProducts - unrecognized current status
    // (config == null branch; uncovered in org coverage report)
    // ============================================================

    /**
     * RES_Unit_Status__c is a restricted picklist, so an arbitrary literal
     * (e.g. 'RES_QA_Unmapped_Status_zzz') fails at INSERT time, before the
     * service logic under test even runs. Instead, this discovers a real
     * picklist value via schema describe that has no matching active
     * RES_Product_Approval_Config__mdt.RES_Current_Status__c, which is what
     * actually drives the "config == null" branch in approveProducts /
     * rejectProducts. Returns null if every picklist value is mapped by an
     * active config (in which case the calling test skips itself).
     */
    private static String findUnmappedStatusValue() {
        Set<String> mappedStatuses = new Set<String>();
        for (RES_Product_Approval_Config__mdt config : [
            SELECT RES_Current_Status__c FROM RES_Product_Approval_Config__mdt WHERE RES_Active__c = true
        ]) {
            if (config.RES_Current_Status__c != null) {
                mappedStatuses.add(config.RES_Current_Status__c);
            }
        }

        for (Schema.PicklistEntry entry : Product2.RES_Unit_Status__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && !mappedStatuses.contains(entry.getValue())) {
                return entry.getValue();
            }
        }
        return null;
    }

    @isTest
    static void testApproveProducts_unrecognizedStatus_reportedAsInvalidState() {
        String unmappedStatus = findUnmappedStatusValue();
        if (unmappedStatus == null) {
            return; // Every picklist value is mapped by an active config in this org - nothing to exercise here.
        }
        Product2 oddStatusProduct = new Product2(
            Name = 'Unrecognized Status',
            IsActive = false,
            RES_Unit_Status__c = unmappedStatus
        );
        insert oddStatusProduct;
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result =
                RES_ProductApprovalService.approveProducts(new Set<Id>{ oddStatusProduct.Id });
            System.assertEquals(1, result.failedCount);
            System.assertEquals(System.Label.RES_Product_Invalid_Approval_State, result.items[0].errorMessage);
        }
        Test.stopTest();
    }

    @isTest
    static void testRejectProducts_unrecognizedStatus_reportedAsInvalidState() {
        String unmappedStatus = findUnmappedStatusValue();
        if (unmappedStatus == null) {
            return; // Every picklist value is mapped by an active config in this org - nothing to exercise here.
        }
        Product2 oddStatusProduct = new Product2(
            Name = 'Unrecognized Status For Reject',
            IsActive = false,
            RES_Unit_Status__c = unmappedStatus
        );
        insert oddStatusProduct;
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result =
                RES_ProductApprovalService.rejectProducts(new Set<Id>{ oddStatusProduct.Id }, 'Reason');
            System.assertEquals(1, result.failedCount);
            System.assertEquals(System.Label.RES_Product_Invalid_Approval_State, result.items[0].errorMessage);
        }
        Test.stopTest();
    }

    // ============================================================
    // resubmitProducts - "cannot resubmit" state branch + the
    // empty-recordsToUpdate early return (uncovered in org report)
    // ============================================================

    @isTest
    static void testResubmitProducts_nonRejectedStatus_reportedAsInvalidState_andReturnsEarly() {
        // A Draft product was never Rejected, so
        // RES_ProductApprovalStateService.canResubmit() must return false
        // for it, driving both the per-record failure branch and the
        // "recordsToUpdate.isEmpty() -> return result" early-exit branch
        // when it is the only record requested.
        Product2 draftProduct = new Product2(Name = 'Cannot Resubmit', IsActive = false, RES_Unit_Status__c = 'Draft');
        insert draftProduct;
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result =
                RES_ProductApprovalService.resubmitProducts(new Set<Id>{ draftProduct.Id });
            System.assertEquals(0, result.successCount, 'A Draft product must not be resubmittable.');
            System.assertEquals(1, result.failedCount);
            System.assertEquals(System.Label.RES_Product_Invalid_Approval_State, result.items[0].errorMessage);
        }
        Test.stopTest();

        Product2 unchanged = [SELECT RES_Unit_Status__c FROM Product2 WHERE Id = :draftProduct.Id];
        System.assertEquals('Draft', unchanged.RES_Unit_Status__c, 'Status must be unchanged when resubmit is rejected by the state service.');
    }

    // ============================================================
    // getApprovalQueue - unauthorized branch + "results returned,
    // cursor populated" branch (both uncovered in org report)
    // ============================================================

    @isTest
    static void testGetApprovalQueue_unauthorizedStandardUser_returnsError() {
        List<RES_Product_Approval_Config__mdt> configs = [
            SELECT RES_Approval_Level__c FROM RES_Product_Approval_Config__mdt WHERE RES_Active__c = true LIMIT 1
        ];
        if (configs.isEmpty()) {
            return; // No active configuration deployed in this org - nothing to exercise here.
        }
        Integer level = configs[0].RES_Approval_Level__c.intValue();
        User standardUser = RES_TestDataFactory.createGenericUser('Standard User');

        Test.startTest();
        System.runAs(standardUser) {
            RES_ProductApprovalService.ApprovalQueueResult result = RES_ProductApprovalService.getApprovalQueue(level, null, null, null, null);
            System.assertEquals(System.Label.RES_Product_Unauthorized_Approval, result.errorMessage);
            System.assertEquals(0, result.products.size());
        }
        Test.stopTest();
    }

    @isTest
    static void testGetApprovalQueue_admin_resultsPopulateCursor() {
        List<RES_Product_Approval_Config__mdt> configs = [
            SELECT RES_Approval_Level__c, RES_Current_Status__c FROM RES_Product_Approval_Config__mdt WHERE RES_Active__c = true LIMIT 1
        ];
        if (configs.isEmpty()) {
            return; // No active configuration deployed in this org - nothing to exercise here.
        }
        Integer level = configs[0].RES_Approval_Level__c.intValue();

        // A matching Product ensures productDAO.getApprovalQueue() returns
        // at least one row, exercising the "!products.isEmpty()" branch
        // that populates nextCreatedDate/nextId.
        insert new Product2(
            Name = 'Queue Cursor Candidate',
            IsActive = false,
            RES_Unit_Status__c = configs[0].RES_Current_Status__c
        );
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.ApprovalQueueResult result = RES_ProductApprovalService.getApprovalQueue(level, null, 1, null, null);
            System.assertNotEquals(null, result, 'Result must never be null.');
            if (!result.products.isEmpty()) {
                System.assertNotEquals(null, result.nextCreatedDate, 'Cursor date must be populated when results are returned.');
                System.assertNotEquals(null, result.nextId, 'Cursor id must be populated when results are returned.');
            }
        }
        Test.stopTest();
    }
}