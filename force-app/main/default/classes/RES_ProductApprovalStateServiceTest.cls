/**
 * ==============================================================================
 * Class Name    : RES_ProductApprovalStateServiceTest
 * Description   : Unit tests for RES_ProductApprovalStateService.
 *
 * Design notes:
 *      - RES_ProductApprovalStateService performs no SOQL and no DML - every
 *        method takes its inputs (Product2, RES_Product_Approval_Config__mdt,
 *        Map, String) directly as parameters. RES_Product_Approval_Config__mdt
 *        instances are therefore constructed in memory (custom metadata types
 *        cannot be inserted via DML, but CAN be instantiated in memory for
 *        logic testing - no CMDT deployment or org data dependency needed).
 *      - No users, DML, or RES_TestDataFactory calls are required - this
 *        class is fully deterministic and self-contained.
 * ==============================================================================
 */
@isTest
private class RES_ProductApprovalStateServiceTest {

    // ============================================================
    // buildStatusConfigMap
    // ============================================================

    @isTest
    static void testBuildStatusConfigMap_nullConfigs_returnsEmptyMap() {
        Map<String, RES_Product_Approval_Config__mdt> result =
            RES_ProductApprovalStateService.buildStatusConfigMap(null);
        System.assertNotEquals(null, result, 'Result must never be null.');
        System.assertEquals(0, result.size());
    }

    @isTest
    static void testBuildStatusConfigMap_emptyList_returnsEmptyMap() {
        Map<String, RES_Product_Approval_Config__mdt> result =
            RES_ProductApprovalStateService.buildStatusConfigMap(new List<RES_Product_Approval_Config__mdt>());
        System.assertEquals(0, result.size());
    }

    @isTest
    static void testBuildStatusConfigMap_skipsNullInactiveAndBlankStatusEntries() {
        RES_Product_Approval_Config__mdt inactiveConfig = new RES_Product_Approval_Config__mdt(
            RES_Active__c = false,
            RES_Current_Status__c = 'Draft'
        );
        RES_Product_Approval_Config__mdt blankStatusConfig = new RES_Product_Approval_Config__mdt(
            RES_Active__c = true,
            RES_Current_Status__c = null
        );
        RES_Product_Approval_Config__mdt validConfig = new RES_Product_Approval_Config__mdt(
            RES_Active__c = true,
            RES_Current_Status__c = 'Draft',
            RES_Next_Status__c = 'Pending Finance Approval'
        );

        List<RES_Product_Approval_Config__mdt> configs = new List<RES_Product_Approval_Config__mdt>{
            null, inactiveConfig, blankStatusConfig, validConfig
        };

        Map<String, RES_Product_Approval_Config__mdt> result = RES_ProductApprovalStateService.buildStatusConfigMap(configs);
        System.assertEquals(1, result.size(), 'Only the single valid, active config with a status must be included.');
        System.assertEquals(true, result.containsKey('Draft'));
        System.assertEquals('Pending Finance Approval', result.get('Draft').RES_Next_Status__c);
    }

    @isTest
    static void testBuildStatusConfigMap_multipleValidConfigs_allIncluded() {
        RES_Product_Approval_Config__mdt draftConfig = new RES_Product_Approval_Config__mdt(
            RES_Active__c = true,
            RES_Current_Status__c = 'Draft'
        );
        RES_Product_Approval_Config__mdt financeConfig = new RES_Product_Approval_Config__mdt(
            RES_Active__c = true,
            RES_Current_Status__c = 'Pending Finance Approval'
        );

        Map<String, RES_Product_Approval_Config__mdt> result = RES_ProductApprovalStateService.buildStatusConfigMap(
            new List<RES_Product_Approval_Config__mdt>{ draftConfig, financeConfig }
        );
        System.assertEquals(2, result.size());
        System.assertEquals(true, result.containsKey('Draft'));
        System.assertEquals(true, result.containsKey('Pending Finance Approval'));
    }

    // ============================================================
    // getConfigForStatus
    // ============================================================

    @isTest
    static void testGetConfigForStatus_blankStatus_returnsNull() {
        Map<String, RES_Product_Approval_Config__mdt> configMap = new Map<String, RES_Product_Approval_Config__mdt>{
            'Draft' => new RES_Product_Approval_Config__mdt(RES_Active__c = true, RES_Current_Status__c = 'Draft')
        };
        System.assertEquals(null, RES_ProductApprovalStateService.getConfigForStatus(null, configMap));
        System.assertEquals(null, RES_ProductApprovalStateService.getConfigForStatus('   ', configMap));
    }

    @isTest
    static void testGetConfigForStatus_nullOrEmptyMap_returnsNull() {
        System.assertEquals(null, RES_ProductApprovalStateService.getConfigForStatus('Draft', null));
        System.assertEquals(null, RES_ProductApprovalStateService.getConfigForStatus('Draft', new Map<String, RES_Product_Approval_Config__mdt>()));
    }

    @isTest
    static void testGetConfigForStatus_statusNotInMap_returnsNull() {
        Map<String, RES_Product_Approval_Config__mdt> configMap = new Map<String, RES_Product_Approval_Config__mdt>{
            'Draft' => new RES_Product_Approval_Config__mdt(RES_Active__c = true, RES_Current_Status__c = 'Draft')
        };
        System.assertEquals(null, RES_ProductApprovalStateService.getConfigForStatus('Rejected', configMap));
    }

    @isTest
    static void testGetConfigForStatus_statusInMap_returnsConfig() {
        RES_Product_Approval_Config__mdt draftConfig = new RES_Product_Approval_Config__mdt(
            RES_Active__c = true,
            RES_Current_Status__c = 'Draft',
            RES_Next_Status__c = 'Pending Finance Approval'
        );
        Map<String, RES_Product_Approval_Config__mdt> configMap = new Map<String, RES_Product_Approval_Config__mdt>{
            'Draft' => draftConfig
        };
        RES_Product_Approval_Config__mdt result = RES_ProductApprovalStateService.getConfigForStatus('Draft', configMap);
        System.assertNotEquals(null, result);
        System.assertEquals('Pending Finance Approval', result.RES_Next_Status__c);
    }

    // ============================================================
    // canApprove
    // ============================================================

    @isTest
    static void testCanApprove_nullProductOrConfig_returnsFalse() {
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(RES_Current_Status__c = 'Draft');
        Product2 product = new Product2(RES_Unit_Status__c = 'Draft');

        System.assertEquals(false, RES_ProductApprovalStateService.canApprove(null, config));
        System.assertEquals(false, RES_ProductApprovalStateService.canApprove(product, null));
        System.assertEquals(false, RES_ProductApprovalStateService.canApprove(null, null));
    }

    @isTest
    static void testCanApprove_blankProductStatus_returnsFalse() {
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(RES_Current_Status__c = 'Draft');
        Product2 product = new Product2(RES_Unit_Status__c = null);
        System.assertEquals(false, RES_ProductApprovalStateService.canApprove(product, config));
    }

    @isTest
    static void testCanApprove_matchingStatus_returnsTrue() {
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(RES_Current_Status__c = 'Draft');
        Product2 product = new Product2(RES_Unit_Status__c = 'Draft');
        System.assertEquals(true, RES_ProductApprovalStateService.canApprove(product, config));
    }

    @isTest
    static void testCanApprove_nonMatchingStatus_returnsFalse() {
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(RES_Current_Status__c = 'Draft');
        Product2 product = new Product2(RES_Unit_Status__c = 'Pending Finance Approval');
        System.assertEquals(false, RES_ProductApprovalStateService.canApprove(product, config));
    }

    // ============================================================
    // getNextStatus
    // ============================================================

    @isTest
    static void testGetNextStatus_nullConfig_returnsNull() {
        System.assertEquals(null, RES_ProductApprovalStateService.getNextStatus(null));
    }

    @isTest
    static void testGetNextStatus_validConfig_returnsNextStatus() {
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(RES_Next_Status__c = 'Pending CSO Approval');
        System.assertEquals('Pending CSO Approval', RES_ProductApprovalStateService.getNextStatus(config));
    }

    // ============================================================
    // isFinalApproval
    // ============================================================

    @isTest
    static void testIsFinalApproval_nullConfig_returnsFalse() {
        System.assertEquals(false, RES_ProductApprovalStateService.isFinalApproval(null));
    }

    @isTest
    static void testIsFinalApproval_trueFlag_returnsTrue() {
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(RES_Final_Level__c = true);
        System.assertEquals(true, RES_ProductApprovalStateService.isFinalApproval(config));
    }

    @isTest
    static void testIsFinalApproval_falseFlag_returnsFalse() {
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt(RES_Final_Level__c = false);
        System.assertEquals(false, RES_ProductApprovalStateService.isFinalApproval(config));
    }

    @isTest
    static void testIsFinalApproval_nullFlag_returnsFalse() {
        RES_Product_Approval_Config__mdt config = new RES_Product_Approval_Config__mdt();
        System.assertEquals(false, RES_ProductApprovalStateService.isFinalApproval(config));
    }

    // ============================================================
    // canReject
    // ============================================================

    @isTest
    static void testCanReject_eachEligibleStatus_returnsTrue() {
        System.assertEquals(true, RES_ProductApprovalStateService.canReject('Draft'));
        System.assertEquals(true, RES_ProductApprovalStateService.canReject('Pending Finance Approval'));
        System.assertEquals(true, RES_ProductApprovalStateService.canReject('Pending CSO Approval'));
    }

    @isTest
    static void testCanReject_ineligibleOrNullStatus_returnsFalse() {
        System.assertEquals(false, RES_ProductApprovalStateService.canReject('Rejected'));
        System.assertEquals(false, RES_ProductApprovalStateService.canReject('Available'));
        System.assertEquals(false, RES_ProductApprovalStateService.canReject(null));
        System.assertEquals(false, RES_ProductApprovalStateService.canReject(''));
    }

    // ============================================================
    // canResubmit
    // ============================================================

    @isTest
    static void testCanResubmit_rejectedStatus_returnsTrue() {
        System.assertEquals(true, RES_ProductApprovalStateService.canResubmit('Rejected'));
    }

    @isTest
    static void testCanResubmit_otherOrNullStatus_returnsFalse() {
        System.assertEquals(false, RES_ProductApprovalStateService.canResubmit('Draft'));
        System.assertEquals(false, RES_ProductApprovalStateService.canResubmit(null));
        System.assertEquals(false, RES_ProductApprovalStateService.canResubmit(''));
    }
}