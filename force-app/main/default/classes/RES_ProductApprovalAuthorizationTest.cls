/**
 * ==============================================================================
 * Class Name    : RES_ProductApprovalAuthorizationTest
 * Description   : Unit tests for RES_ProductApprovalAuthorization.
 *
 * Design notes:
 *      - RES_Product_Approval_Config__mdt records are constructed in-memory
 *        (custom metadata types cannot be inserted via DML, but CAN be
 *        instantiated in memory for logic testing - no DML/deploy needed).
 *      - System Administrator paths are exercised via System.runAs() with a
 *        user assigned the 'System Administrator' profile.
 *      - Non-admin / Custom Permission paths do not depend on any Custom
 *        Permission actually being assigned in the org - they rely on the
 *        deterministic "not assigned => false" behavior, so this test class
 *        has no external setup dependency.
 *      - User creation is delegated to RES_TestDataFactory.createGenericUser(),
 *        which creates a bare user for a given Profile with no Role/Permission
 *        Set assumptions - a good fit here since Product Approval authorization
 *        is Profile + Custom Permission driven, not Role/Sales-Permission-Set
 *        driven like RES_TestDataFactory's Sales-specific user methods.
 * ==============================================================================
 */
@isTest
private class RES_ProductApprovalAuthorizationTest {

    @isTest
    static void testHasCustomPermission_blankName_returnsFalse() {
        System.assertEquals(false, RES_ProductApprovalAuthorization.hasCustomPermission(null), 'Blank/null permission name must return false.');
        System.assertEquals(false, RES_ProductApprovalAuthorization.hasCustomPermission(''), 'Empty permission name must return false.');
    }

    @isTest
    static void testHasCustomPermission_unassignedPermission_returnsFalse() {
        // Permission name is syntactically valid but not assigned/granted to the running user.
        Boolean result = RES_ProductApprovalAuthorization.hasCustomPermission('RES_Product_Operation_Visibility');
        System.assertEquals(false, result, 'Unassigned custom permission should return false, not throw.');
    }

    @isTest
    static void testCanActOnConfig_nullConfig_returnsFalse() {
        System.assertEquals(false, RES_ProductApprovalAuthorization.canActOnConfig(null));
    }

    @isTest
    static void testCanActOnConfig_inactiveConfig_returnsFalse() {
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(
            RES_Active__c = false,
            RES_Custom_Permission__c = 'RES_Product_Operation_Visibility'
        );
        System.assertEquals(false, RES_ProductApprovalAuthorization.canActOnConfig(config));
    }

    @isTest
    static void testCanActOnConfig_blankCustomPermission_returnsFalse() {
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(
            RES_Active__c = true,
            RES_Custom_Permission__c = null
        );
        System.assertEquals(false, RES_ProductApprovalAuthorization.canActOnConfig(config));
    }

    @isTest
    static void testCanActOnConfig_activeButUnassignedPermission_returnsFalse() {
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(
            RES_Active__c = true,
            RES_Custom_Permission__c = 'RES_Product_Operation_Visibility'
        );
        System.assertEquals(false, RES_ProductApprovalAuthorization.canActOnConfig(config));
    }

    @isTest
    static void testCanViewConfig_nullConfig_returnsFalse() {
        System.assertEquals(false, RES_ProductApprovalAuthorization.canViewConfig(null));
    }

    @isTest
    static void testCanApprove_nullConfig_returnsFalse() {
        System.assertEquals(false, RES_ProductApprovalAuthorization.canApprove(null));
    }

    @isTest
    static void testCanReject_nullConfig_returnsFalse() {
        System.assertEquals(false, RES_ProductApprovalAuthorization.canReject(null));
    }

    @isTest
    static void testCanViewConfig_nonAdmin_noPermission_returnsFalse() {
        User standardUser = RES_TestDataFactory.createGenericUser('Standard User');
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(
            RES_Active__c = true,
            RES_Custom_Permission__c = 'RES_Product_Operation_Visibility'
        );

        System.runAs(standardUser) {
            Boolean result = RES_ProductApprovalAuthorization.canViewConfig(config);
            System.assertEquals(false, result, 'Standard user without the custom permission must not view the queue.');
        }
    }

    @isTest
    static void testCanApprove_nonAdmin_noPermission_returnsFalse() {
        User standardUser = RES_TestDataFactory.createGenericUser('Standard User');
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(
            RES_Active__c = true,
            RES_Custom_Permission__c = 'RES_Product_Operation_Visibility'
        );

        System.runAs(standardUser) {
            Boolean result = RES_ProductApprovalAuthorization.canApprove(config);
            System.assertEquals(false, result, 'Standard user without the custom permission must not approve.');
        }
    }

    @isTest
    static void testCanReject_nonAdmin_noPermission_returnsFalse() {
        User standardUser = RES_TestDataFactory.createGenericUser('Standard User');
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(
            RES_Active__c = true,
            RES_Custom_Permission__c = 'RES_Product_Operation_Visibility'
        );

        System.runAs(standardUser) {
            Boolean result = RES_ProductApprovalAuthorization.canReject(config);
            System.assertEquals(false, result, 'Standard user without the custom permission must not reject.');
        }
    }

    @isTest
    static void testCanResubmit_nonAdmin_noPermission_returnsFalse() {
        User standardUser = RES_TestDataFactory.createGenericUser('Standard User');

        System.runAs(standardUser) {
            Boolean result = RES_ProductApprovalAuthorization.canResubmit();
            System.assertEquals(false, result, 'Standard user without operations permission must not resubmit.');
        }
    }

    // NOTE: A dedicated test for hasCustomPermission()'s catch branch was
    // intentionally omitted. FeatureManagement.checkPermission() does not
    // throw a normal, catchable Exception for a syntactically malformed
    // name - it raises a platform-level System.UnexpectedException that
    // bypasses ordinary try/catch handling entirely (confirmed via a failed
    // test run). A syntactically valid but non-existent permission name, on
    // the other hand, simply returns false without throwing at all. Neither
    // input reliably exercises the catch block, so it's left uncovered
    // rather than adding a test that either crashes or doesn't test what it
    // claims to.

    @isTest
    static void testSystemAdministrator_fullAccess_allPaths() {
        User adminUser = RES_TestDataFactory.createGenericUser('System Administrator');
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(
            RES_Active__c = true,
            RES_Custom_Permission__c = 'RES_Product_Operation_Visibility'
        );

        System.runAs(adminUser) {
            System.assertEquals(true, RES_ProductApprovalAuthorization.canViewConfig(config), 'Admin must view any active queue.');
            System.assertEquals(true, RES_ProductApprovalAuthorization.canApprove(config), 'Admin must be able to approve at any stage.');
            System.assertEquals(true, RES_ProductApprovalAuthorization.canReject(config), 'Admin must be able to reject at any stage.');
            System.assertEquals(true, RES_ProductApprovalAuthorization.canResubmit(), 'Admin must be able to resubmit.');
            // Confirms the transaction-scoped cache is consistent across repeated calls.
            System.assertEquals(true, RES_ProductApprovalAuthorization.canApprove(config), 'Cached admin flag must remain true on repeat calls.');
        }
    }
}