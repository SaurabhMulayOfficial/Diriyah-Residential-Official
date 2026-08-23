/**
 * ==============================================================================
 * Class Name    : RES_ProductApprovalControllerTest
 * Description   : Unit tests for RES_ProductApprovalController.
 *
 * Design notes:
 *      - The Controller is a thin delegate: every public method's job is to
 *        (a) convert a List<Id> parameter to Set<Id> where needed, (b) call
 *        the matching RES_ProductApprovalService method, and (c) translate
 *        any exception into an AuraHandledException. These tests exercise
 *        every delegate call as a System Administrator (so the underlying
 *        service methods succeed rather than short-circuit on
 *        authorization), plus the null-List defensive conversion.
 *      - User creation is delegated to RES_TestDataFactory.createGenericUser().
 *      - RES_ProductApprovalService never throws for any legitimate input -
 *        every expected failure is returned as an error message on the
 *        result wrapper instead - so the catch/createAuraException() path
 *        in the controller has no naturally reachable trigger. The
 *        "_exceptionPath_" tests below use the controller's @TestVisible
 *        forceExceptionForTests / forcedExceptionMessage seam (test-only,
 *        no production behavior change) to genuinely exercise that path
 *        rather than leaving it permanently uncovered.
 * ==============================================================================
 */
@isTest
private class RES_ProductApprovalControllerTest {

    /**
     * Ensures the test-only exception seam is off before/after every test,
     * regardless of pass/fail, so no state can leak between test methods.
     */
    private static void resetExceptionSeam() {
        RES_ProductApprovalController.forceExceptionForTests = false;
        RES_ProductApprovalController.forcedExceptionMessage = null;
    }

    @isTest
    static void testGetUserApprovalAccess_delegatesToService() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.ApprovalAccessResult result = RES_ProductApprovalController.getUserApprovalAccess();
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertEquals(true, result.canViewRejected, 'System Administrator must be able to view the rejected queue.');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetUserApprovalAccess_exceptionPath_wrapsAsAuraHandledException() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');
        resetExceptionSeam();
        RES_ProductApprovalController.forceExceptionForTests = true;
        RES_ProductApprovalController.forcedExceptionMessage = 'Forced failure for getUserApprovalAccess';

        Test.startTest();
        System.runAs(admin) {
            try {
                RES_ProductApprovalController.getUserApprovalAccess();
                System.assert(false, 'Expected an AuraHandledException to be thrown.');
            } catch (AuraHandledException ex) {
                System.assertEquals('Forced failure for getUserApprovalAccess', ex.getMessage());
            } finally {
                resetExceptionSeam();
            }
        }
        Test.stopTest();
    }

    @isTest
    static void testGetApprovalQueue_delegatesToService() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.ApprovalQueueResult result =
                RES_ProductApprovalController.getApprovalQueue(null, null, null, null, null);
            System.assertNotEquals(null, result, 'Result must never be null.');
            // Level is null in this call, so the underlying service returns
            // its standard validation error rather than throwing - confirms
            // the controller passes parameters straight through unmodified.
            System.assertEquals(System.Label.RES_Product_Invalid_Approval_State, result.errorMessage);
        }
        Test.stopTest();
    }

    @isTest
    static void testGetApprovalQueue_exceptionPath_wrapsAsAuraHandledException() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');
        resetExceptionSeam();
        RES_ProductApprovalController.forceExceptionForTests = true;
        RES_ProductApprovalController.forcedExceptionMessage = 'Forced failure for getApprovalQueue';

        Test.startTest();
        System.runAs(admin) {
            try {
                RES_ProductApprovalController.getApprovalQueue(1, null, null, null, null);
                System.assert(false, 'Expected an AuraHandledException to be thrown.');
            } catch (AuraHandledException ex) {
                System.assertEquals('Forced failure for getApprovalQueue', ex.getMessage());
            } finally {
                resetExceptionSeam();
            }
        }
        Test.stopTest();
    }

    @isTest
    static void testApproveProducts_nullList_convertsToEmptySet() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalController.approveProducts(null);
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertEquals(System.Label.RES_Product_No_Records_Selected, result.errorMessage,
                'A null List<Id> must be converted to an empty Set<Id>, not passed through as null.');
        }
        Test.stopTest();
    }

    @isTest
    static void testApproveProducts_withIds_delegatesToService() {
        Product2 product = new Product2(Name = 'Controller Approve Candidate', IsActive = false, RES_Unit_Status__c = 'Draft');
        insert product;
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result =
                RES_ProductApprovalController.approveProducts(new List<Id>{ product.Id });
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertEquals(1, result.successCount + result.failedCount, 'Exactly one item must be reported for one requested id.');
        }
        Test.stopTest();
    }

    @isTest
    static void testApproveProducts_exceptionPath_wrapsAsAuraHandledException() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');
        resetExceptionSeam();
        RES_ProductApprovalController.forceExceptionForTests = true;
        // Left null deliberately here to exercise createAuraException()'s
        // "blank message -> generic fallback" branch (both branches share
        // the same executable line, so either is sufficient for coverage;
        // this also confirms the fallback text is actually returned).
        RES_ProductApprovalController.forcedExceptionMessage = null;

        Test.startTest();
        System.runAs(admin) {
            try {
                RES_ProductApprovalController.approveProducts(new List<Id>());
                System.assert(false, 'Expected an AuraHandledException to be thrown.');
            } catch (AuraHandledException ex) {
                System.assertEquals('An unexpected error occurred.', ex.getMessage(),
                    'A blank forced exception message must fall back to the generic message.');
            } finally {
                resetExceptionSeam();
            }
        }
        Test.stopTest();
    }

    @isTest
    static void testRejectProducts_nullList_convertsToEmptySet() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalController.rejectProducts(null, 'reason');
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertEquals(System.Label.RES_Product_No_Records_Selected, result.errorMessage);
        }
        Test.stopTest();
    }

    @isTest
    static void testRejectProducts_withIds_delegatesToService() {
        Product2 product = new Product2(Name = 'Controller Reject Candidate', IsActive = false, RES_Unit_Status__c = 'Draft');
        insert product;
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result =
                RES_ProductApprovalController.rejectProducts(new List<Id>{ product.Id }, 'Not compliant');
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertEquals(1, result.successCount + result.failedCount, 'Exactly one item must be reported for one requested id.');
        }
        Test.stopTest();
    }

    @isTest
    static void testRejectProducts_exceptionPath_wrapsAsAuraHandledException() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');
        resetExceptionSeam();
        RES_ProductApprovalController.forceExceptionForTests = true;
        RES_ProductApprovalController.forcedExceptionMessage = 'Forced failure for rejectProducts';

        Test.startTest();
        System.runAs(admin) {
            try {
                RES_ProductApprovalController.rejectProducts(new List<Id>(), 'reason');
                System.assert(false, 'Expected an AuraHandledException to be thrown.');
            } catch (AuraHandledException ex) {
                System.assertEquals('Forced failure for rejectProducts', ex.getMessage());
            } finally {
                resetExceptionSeam();
            }
        }
        Test.stopTest();
    }

    @isTest
    static void testResubmitProducts_nullList_convertsToEmptySet() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result = RES_ProductApprovalController.resubmitProducts(null);
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertEquals(System.Label.RES_Product_No_Records_Selected, result.errorMessage);
        }
        Test.stopTest();
    }

    @isTest
    static void testResubmitProducts_withIds_delegatesToService() {
        Product2 product = new Product2(
            Name = 'Controller Resubmit Candidate',
            IsActive = false,
            RES_Unit_Status__c = 'Rejected'
        );
        insert product;
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.BulkApprovalResult result =
                RES_ProductApprovalController.resubmitProducts(new List<Id>{ product.Id });
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertEquals(1, result.successCount + result.failedCount, 'Exactly one item must be reported for one requested id.');
        }
        Test.stopTest();
    }

    @isTest
    static void testResubmitProducts_exceptionPath_wrapsAsAuraHandledException() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');
        resetExceptionSeam();
        RES_ProductApprovalController.forceExceptionForTests = true;
        RES_ProductApprovalController.forcedExceptionMessage = 'Forced failure for resubmitProducts';

        Test.startTest();
        System.runAs(admin) {
            try {
                RES_ProductApprovalController.resubmitProducts(new List<Id>());
                System.assert(false, 'Expected an AuraHandledException to be thrown.');
            } catch (AuraHandledException ex) {
                System.assertEquals('Forced failure for resubmitProducts', ex.getMessage());
            } finally {
                resetExceptionSeam();
            }
        }
        Test.stopTest();
    }

    @isTest
    static void testGetRejectedProducts_delegatesToService() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');

        Test.startTest();
        System.runAs(admin) {
            RES_ProductApprovalService.ApprovalQueueResult result =
                RES_ProductApprovalController.getRejectedProducts(null, null, null, null);
            System.assertNotEquals(null, result, 'Result must never be null.');
            System.assertNotEquals(null, result.products, 'Products list must never be null.');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetRejectedProducts_unauthorizedUser_returnsError() {
        User standardUser = RES_TestDataFactory.createGenericUser('Standard User');

        Test.startTest();
        System.runAs(standardUser) {
            RES_ProductApprovalService.ApprovalQueueResult result =
                RES_ProductApprovalController.getRejectedProducts(null, null, null, null);
            System.assertEquals(System.Label.RES_Product_Unauthorized_Approval, result.errorMessage);
        }
        Test.stopTest();
    }

    @isTest
    static void testGetRejectedProducts_exceptionPath_wrapsAsAuraHandledException() {
        User admin = RES_TestDataFactory.createGenericUser('System Administrator');
        resetExceptionSeam();
        RES_ProductApprovalController.forceExceptionForTests = true;
        RES_ProductApprovalController.forcedExceptionMessage = 'Forced failure for getRejectedProducts';

        Test.startTest();
        System.runAs(admin) {
            try {
                RES_ProductApprovalController.getRejectedProducts(null, null, null, null);
                System.assert(false, 'Expected an AuraHandledException to be thrown.');
            } catch (AuraHandledException ex) {
                System.assertEquals('Forced failure for getRejectedProducts', ex.getMessage());
            } finally {
                resetExceptionSeam();
            }
        }
        Test.stopTest();
    }
}