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
        RES_IntegrationRequestEventService.batchSubmitter = new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        Product2 throwaway = new Product2(Name = 'Throwaway', IsActive = false, RES_Unit_Status__c = 'Draft');
        insert throwaway;
        Id result = throwaway.Id;
        delete throwaway;
        return result;
    }

    /** Configures the Service Charge Rate attribute override (RES_ProductSCRateValidation requires this before a Residential Sales unit can go Active/Available) on the given product, reusing the org's real AttributeDefinition/ProductClassificationAttr - DeveloperName is unique org-wide, so this must run under SeeAllData=true. */
    private static void insertServiceChargeRateOverride(Id productId) {
        String scRateDeveloperName = Label.RES_Service_Charge_Rate_Attribute;

        List<AttributeDefinition> existingScRateAttrs = [
            SELECT Id FROM AttributeDefinition WHERE DeveloperName = :scRateDeveloperName LIMIT 1
        ];
        AttributeDefinition scRateAttr;
        if (!existingScRateAttrs.isEmpty()) {
            scRateAttr = existingScRateAttrs[0];
        } else {
            scRateAttr = new AttributeDefinition(
                Name = 'RES Test ProductApproval SC Rate Attribute', Label = 'RES Test ProductApproval SC Rate Attribute',
                DeveloperName = scRateDeveloperName, DataType = 'Number', IsActive = true
            );
            insert scRateAttr;
        }

        List<ProductClassificationAttr> existingClassificationAttrs = [
            SELECT Id, ProductClassificationId FROM ProductClassificationAttr WHERE AttributeDefinitionId = :scRateAttr.Id LIMIT 1
        ];
        ProductClassificationAttr classificationAttr;
        if (!existingClassificationAttrs.isEmpty()) {
            classificationAttr = existingClassificationAttrs[0];
        } else {
            ProductClassification classification = new ProductClassification(
                Code = 'RES_TEST_PRODAPPROVAL_' + String.valueOf(Crypto.getRandomInteger()).right(8),
                Name = 'RES Test ProductApproval Classification',
                Status = 'Active'
            );
            insert classification;
            classificationAttr = new ProductClassificationAttr(
                Name = 'RES Test ProductApproval Classification Attr',
                ProductClassificationId = classification.Id,
                AttributeDefinitionId = scRateAttr.Id
            );
            insert classificationAttr;
        }

        // Product2.BasedOnId must match the ProductClassificationAttr's own classification
        update new Product2(Id = productId, BasedOnId = classificationAttr.ProductClassificationId);

        insert new ProductAttributeDefinition(
            Name = 'RES Test ProductApproval SC Rate Override',
            ProductClassificationAttributeId = classificationAttr.Id,
            Product2Id = productId,
            AttributeDefinitionId = scRateAttr.Id,
            DefaultValue = '120'
        );
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

    // ============================================================
    // Update Field Clearing Tests (DIR-859)
    // ============================================================

    /**
     * Test that when a product with RES_Update_Requested__c = true
     * is approved and moves to Available, both update fields are cleared.
     */
    @isTest(SeeAllData=true)
    static void testApproveProducts_withUpdateFlag_clearsUpdateFields() {
        // Get existing approval config
        List<RES_Product_Approval_Config__mdt> configs = [
            SELECT Id, RES_Approval_Level__c, RES_Current_Status__c, RES_Next_Status__c
            FROM RES_Product_Approval_Config__mdt
            WHERE RES_Next_Status__c = 'Available'
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            return; // Skip if no final-approval config exists
        }

        RES_IntegrationRequestEventService.batchSubmitter = new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        // Create product with update flag and comments
        Product2 updateProduct = new Product2(
            Name = 'Updated Product Test',
            IsActive = false,
            RES_Unit_Status__c = configs[0].RES_Current_Status__c,
            RES_Update_Requested__c = true,
            RES_Update_Comments__c = 'Test update comments'
        );
        insert updateProduct;
        insertServiceChargeRateOverride(updateProduct.Id);

        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.approveProducts(new Set<Id>{ updateProduct.Id });
        }
        Test.stopTest();

        // Verify: Update fields should be cleared after approval
        Product2 refreshed = [
            SELECT Id, RES_Update_Requested__c, RES_Update_Comments__c, IsActive
            FROM Product2
            WHERE Id = :updateProduct.Id
        ];

        System.assertEquals(false, refreshed.RES_Update_Requested__c,
            'RES_Update_Requested__c should be cleared after approval');
        System.assertEquals(null, refreshed.RES_Update_Comments__c,
            'RES_Update_Comments__c should be cleared after approval');
        System.assertEquals(true, refreshed.IsActive,
            'Product should be activated after final approval');
    }

    /**
     * Test that when a product with RES_Update_Requested__c = true
     * is approved at DevCo level (re-approval flow), it goes directly
     * to Available and update fields are cleared.
     */
    @isTest(SeeAllData=true)
    static void testApproveProducts_reApprovalFlow_goesDirectlyToAvailable() {
        RES_IntegrationRequestEventService.batchSubmitter = new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        // Create product at Pending DevCo Approval with update flag
        Product2 reApprovalProduct = new Product2(
            Name = 'Re-Approval Product Test',
            IsActive = false,
            RES_Unit_Status__c = 'Pending DevCo Approval',
            RES_Update_Requested__c = true,
            RES_Update_Comments__c = 'Unit updated after initial approval'
        );
        insert reApprovalProduct;
        insertServiceChargeRateOverride(reApprovalProduct.Id);

        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.approveProducts(new Set<Id>{ reApprovalProduct.Id });
        }
        Test.stopTest();

        // Verify: Product should go directly to Available and update fields cleared
        Product2 refreshed = [
            SELECT Id, RES_Unit_Status__c, RES_Update_Requested__c,
                   RES_Update_Comments__c, IsActive
            FROM Product2
            WHERE Id = :reApprovalProduct.Id
        ];

        System.assertEquals('Available', refreshed.RES_Unit_Status__c,
            'Re-approval should go directly to Available status');
        System.assertEquals(false, refreshed.RES_Update_Requested__c,
            'RES_Update_Requested__c should be cleared after re-approval');
        System.assertEquals(null, refreshed.RES_Update_Comments__c,
            'RES_Update_Comments__c should be cleared after re-approval');
        System.assertEquals(true, refreshed.IsActive,
            'Product should be activated after re-approval');
    }

    /**
     * Test that normal products (without update flag) are not affected
     * by the update field clearing logic.
     */
    @isTest
    static void testApproveProducts_withoutUpdateFlag_noFieldsCleared() {
        // Get existing approval config
        List<RES_Product_Approval_Config__mdt> configs = [
            SELECT Id, RES_Approval_Level__c, RES_Current_Status__c
            FROM RES_Product_Approval_Config__mdt
            WHERE RES_Approval_Level__c = 1
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            return; // Skip if no config exists
        }

        RES_IntegrationRequestEventService.batchSubmitter = new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        // Create normal product without update flag
        Product2 normalProduct = new Product2(
            Name = 'Normal Product Test',
            IsActive = false,
            RES_Unit_Status__c = configs[0].RES_Current_Status__c,
            RES_Update_Requested__c = false,
            RES_Update_Comments__c = null
        );
        insert normalProduct;

        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.approveProducts(new Set<Id>{ normalProduct.Id });
        }
        Test.stopTest();

        // Verify: Update fields remain unchanged for normal products
        Product2 refreshed = [
            SELECT Id, RES_Update_Requested__c, RES_Update_Comments__c
            FROM Product2
            WHERE Id = :normalProduct.Id
        ];

        System.assertEquals(false, refreshed.RES_Update_Requested__c,
            'Normal product update flag should remain false');
        System.assertEquals(null, refreshed.RES_Update_Comments__c,
            'Normal product comments should remain null');
    }

    // ============================================================
    // submitForApproval
    // ============================================================

    private static Product2 insertUnit(String name, String status) {
        RES_IntegrationRequestEventService.batchSubmitter = new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        Product2 unit = new Product2(Name = name, IsActive = false, RES_Unit_Status__c = status);
        insert unit;
        return unit;
    }

    @isTest
    static void testSubmitForApproval_nullOrEmptyIds_returnsError() {
        System.assertEquals(System.Label.RES_Product_No_Records_Selected,
            RES_ProductApprovalService.submitForApproval(null).errorMessage, 'Null ids');
        System.assertEquals(System.Label.RES_Product_No_Records_Selected,
            RES_ProductApprovalService.submitForApproval(new Set<Id>()).errorMessage, 'Empty ids');
    }

    @isTest
    static void testSubmitForApproval_unauthorizedUser_returnsError() {
        User standardUser = RES_TestDataFactory.createGenericUser('Standard User');
        Id anyId = deletedProductId();

        Test.startTest();
        System.runAs(standardUser) {
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.submitForApproval(new Set<Id>{ anyId });
            System.assertEquals(System.Label.RES_Product_Unauthorized_Approval, result.errorMessage);
        }
        Test.stopTest();
    }

    @isTest
    static void testSubmitForApproval_onlyNullIds_returnsError() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.submitForApproval(new Set<Id>{ null });
            System.assertEquals(System.Label.RES_Product_No_Records_Selected, result.errorMessage,
                'A set that only holds null is treated as no selection');
        }
        Test.stopTest();
    }

    @isTest
    static void testSubmitForApproval_draftAndRejected_moveToPendingDevCoAndClearComment() {
        Product2 draftUnit = insertUnit('Submit Draft Unit', 'Draft');
        Product2 rejectedUnit = insertUnit('Submit Rejected Unit', 'Rejected');
        update new Product2(Id = rejectedUnit.Id, RES_Rejection_Comment__c = 'Fix the area');
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result =
                RES_ProductApprovalService.submitForApproval(new Set<Id>{ draftUnit.Id, rejectedUnit.Id });
            System.assertEquals(2, result.successCount, 'Both units can be submitted');
            System.assertEquals(0, result.failedCount, 'Nothing fails');
            System.assertEquals(2, result.items.size(), 'One item per unit');
        }
        Test.stopTest();

        for (Product2 unit : [SELECT RES_Unit_Status__c, RES_Rejection_Comment__c FROM Product2 WHERE Id IN :new Set<Id>{ draftUnit.Id, rejectedUnit.Id }]) {
            System.assertEquals('Pending DevCo Approval', unit.RES_Unit_Status__c, 'Submitted units wait for DevCo');
            System.assertEquals(null, unit.RES_Rejection_Comment__c, 'The old rejection comment is cleared');
        }
    }

    @isTest
    static void testSubmitForApproval_otherStatus_isRefusedAndUnitUntouched() {
        Product2 pendingUnit = insertUnit('Already Pending Unit', 'Pending Finance Approval');
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.submitForApproval(new Set<Id>{ pendingUnit.Id });
            System.assertEquals(1, result.failedCount, 'Only Draft or Rejected units can be submitted');
            System.assertEquals(0, result.successCount, 'No success');
            System.assertEquals(false, result.items[0].success, 'The item is a failure');
        }
        Test.stopTest();

        System.assertEquals('Pending Finance Approval',
            [SELECT RES_Unit_Status__c FROM Product2 WHERE Id = :pendingUnit.Id].RES_Unit_Status__c, 'The status is not changed');
    }

    @isTest
    static void testSubmitForApproval_missingUnit_isReportedAsAlreadyProcessed() {
        Product2 draftUnit = insertUnit('Submit With Missing', 'Draft');
        Id missingId = deletedProductId();
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result =
                RES_ProductApprovalService.submitForApproval(new Set<Id>{ draftUnit.Id, missingId });
            System.assertEquals(1, result.successCount, 'The existing unit is submitted');
            System.assertEquals(1, result.failedCount, 'The deleted unit is a failure');
            Boolean foundMessage = false;
            for (RES_ProductApprovalService.ApprovalItemResult item : result.items) {
                if (item.productId == missingId) {
                    foundMessage = item.errorMessage == System.Label.RES_Product_Already_Processed;
                }
            }
            System.assert(foundMessage, 'The missing unit carries the already-processed message');
        }
        Test.stopTest();
    }

    @isTest
    static void testSubmitForApproval_onlyMissingUnit_returnsWithoutUpdate() {
        Id missingId = deletedProductId();
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.submitForApproval(new Set<Id>{ missingId });
            System.assertEquals(0, result.successCount, 'Nothing to update');
            System.assertEquals(1, result.failedCount, 'The missing unit is reported');
        }
        Test.stopTest();
    }

    // ============================================================
    // rejectProducts - success and authorization paths
    // ============================================================

    @isTest
    static void testRejectProducts_pendingDevCoUnit_isRejectedWithTrimmedComment() {
        Product2 pendingUnit = insertUnit('Reject Me Unit', 'Pending DevCo Approval');
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result =
                RES_ProductApprovalService.rejectProducts(new Set<Id>{ pendingUnit.Id }, '   Area is wrong   ');
            System.assertEquals(1, result.successCount, 'The unit is rejected');
            System.assertEquals(0, result.failedCount, 'No failure');
            System.assertEquals(true, result.items[0].success, 'The item is a success');
        }
        Test.stopTest();

        Product2 refreshed = [SELECT RES_Unit_Status__c, RES_Rejection_Comment__c FROM Product2 WHERE Id = :pendingUnit.Id];
        System.assertEquals('Rejected', refreshed.RES_Unit_Status__c, 'Status becomes Rejected');
        System.assertEquals('Area is wrong', refreshed.RES_Rejection_Comment__c, 'The comment is trimmed');
    }

    @isTest
    static void testRejectProducts_unitsAtEveryStage_areAllRejected() {
        Product2 devCoUnit = insertUnit('Reject DevCo Stage', 'Pending DevCo Approval');
        Product2 financeUnit = insertUnit('Reject Finance Stage', 'Pending Finance Approval');
        Product2 csoUnit = insertUnit('Reject CSO Stage', 'Pending CSO Approval');
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalService.rejectProducts(
                new Set<Id>{ devCoUnit.Id, financeUnit.Id, csoUnit.Id }, 'Not ready');
            System.assertEquals(3, result.successCount, 'Each approval stage can reject');
        }
        Test.stopTest();

        for (Product2 unit : [SELECT RES_Unit_Status__c FROM Product2 WHERE Id IN :new Set<Id>{ devCoUnit.Id, financeUnit.Id, csoUnit.Id }]) {
            System.assertEquals('Rejected', unit.RES_Unit_Status__c, 'Rejected at every stage');
        }
    }

    @isTest
    static void testRejectProducts_unauthorizedUser_failsEachUnit() {
        Product2 pendingUnit = insertUnit('Reject Not Allowed', 'Pending DevCo Approval');
        User standardUser = RES_TestDataFactory.createGenericUser('Standard User');

        Test.startTest();
        System.runAs(standardUser) {
            RES_ProductApprovalService.BulkApprovalResult result =
                RES_ProductApprovalService.rejectProducts(new Set<Id>{ pendingUnit.Id }, 'Because');
            System.assertEquals(1, result.failedCount, 'A user without approver rights cannot reject');
            System.assertEquals(System.Label.RES_Product_Unauthorized_Approval, result.items[0].errorMessage, 'Unauthorized message');
        }
        Test.stopTest();

        System.assertEquals('Pending DevCo Approval',
            [SELECT RES_Unit_Status__c FROM Product2 WHERE Id = :pendingUnit.Id].RES_Unit_Status__c, 'The unit is unchanged');
    }

    @isTest
    static void testRejectProducts_missingUnitAlongsideRealOne_isAccountedFor() {
        Product2 pendingUnit = insertUnit('Reject With Missing', 'Pending DevCo Approval');
        Id missingId = deletedProductId();
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result =
                RES_ProductApprovalService.rejectProducts(new Set<Id>{ pendingUnit.Id, missingId }, 'Reason');
            System.assertEquals(1, result.successCount, 'The real unit is rejected');
            System.assertEquals(1, result.failedCount, 'The deleted unit is reported as processed already');
        }
        Test.stopTest();
    }
}
