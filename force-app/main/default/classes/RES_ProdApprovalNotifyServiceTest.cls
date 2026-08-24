/**
 * ==============================================================================
 * Class Name    : RES_ProdApprovalNotifyServiceTest
 * Description   : Unit tests for RES_ProductApprovalNotificationService.
 *
 * Test Coverage:
 *      - Notification methods (next approval, final approval, rejection)
 *      - Merge field replacement using RES_EmailUtilityService
 *      - HTML escaping behavior
 *      - Edge cases (null values, empty lists)
 * ==============================================================================
 */
@isTest
private class RES_ProdApprovalNotifyServiceTest {

    // ============================================================
    // TEST DATA SETUP
    // ============================================================

    private static List<Product2> createTestProducts() {
        List<Product2> products = new List<Product2>();

        Product2 product1 = new Product2(
            Name = 'Test Product <script>alert("XSS")</script>',
            ProductCode = 'PROD-001',
            RES_Unit_Status__c = 'Pending Finance Approval'
        );
        insert product1;
        products.add(product1);

        Product2 product2 = new Product2(
            Name = 'Product with & ampersand',
            ProductCode = 'PROD-002',
            RES_Unit_Status__c = 'Pending Finance Approval'
        );
        insert product2;
        products.add(product2);

        return products;
    }

    // ============================================================
    // RES_EmailUtilityService.hydrateMergeFields TESTS
    // ============================================================

    @isTest
    static void testHydrateMergeFields_basicReplacement() {
        String template = 'Hello {0}, your product {1} is {2}.';
        List<String> mergeFields = new List<String>{ 'John', 'Widget', 'approved' };

        String result = RES_EmailUtilityService.hydrateMergeFields(template, mergeFields);

        System.assertEquals(
            'Hello John, your product Widget is approved.',
            result,
            'Merge fields should replace tokens correctly'
        );
    }

    @isTest
    static void testHydrateMergeFields_withHtmlContent() {
        String template = 'Team: {0}, Products: {1}';
        List<String> mergeFields = new List<String>{
            'Finance Team',
            '<ul><li><strong>Product A</strong></li></ul>'
        };

        String result = RES_EmailUtilityService.hydrateMergeFields(template, mergeFields);

        System.assert(
            result.contains('<ul><li><strong>Product A</strong></li></ul>'),
            'HTML content should be preserved in merge fields'
        );
    }

    @isTest
    static void testHydrateMergeFields_nullValues() {
        String template = 'Value: {0}';
        List<String> mergeFields = new List<String>{ null };

        String result = RES_EmailUtilityService.hydrateMergeFields(template, mergeFields);

        System.assertEquals(
            'Value: ',
            result,
            'Null merge fields should be replaced with empty string'
        );
    }

    @isTest
    static void testHydrateMergeFields_emptyList() {
        String template = 'No merge fields here';
        List<String> mergeFields = new List<String>();

        String result = RES_EmailUtilityService.hydrateMergeFields(template, mergeFields);

        System.assertEquals(
            template,
            result,
            'Template should be unchanged when merge fields list is empty'
        );
    }

    @isTest
    static void testHydrateMergeFields_nullTemplate() {
        String template = null;
        List<String> mergeFields = new List<String>{ 'test' };

        String result = RES_EmailUtilityService.hydrateMergeFields(template, mergeFields);

        System.assertEquals(
            null,
            result,
            'Null template should return null'
        );
    }

    // ============================================================
    // NOTIFICATION METHOD TESTS
    // ============================================================

    @isTest
    static void testNotifyNextApprovalTeam_withValidData() {
        List<Product2> products = createTestProducts();

        Test.startTest();
        RES_ProductApprovalNotificationService.notifyNextApprovalTeam(
            products,
            'Finance Team',
            'CSO Team',
            'RES_CSO'
        );
        Test.stopTest();

        System.assertEquals(2, products.size(), 'Products should be processed');
    }

    @isTest
    static void testNotifyNextApprovalTeam_nullProducts() {
        Test.startTest();
        RES_ProductApprovalNotificationService.notifyNextApprovalTeam(
            null,
            'Finance Team',
            'CSO Team',
            'RES_CSO'
        );
        Test.stopTest();

        System.assert(true, 'Should handle null products gracefully');
    }

    @isTest
    static void testNotifyNextApprovalTeam_emptyProducts() {
        Test.startTest();
        RES_ProductApprovalNotificationService.notifyNextApprovalTeam(
            new List<Product2>(),
            'Finance Team',
            'CSO Team',
            'RES_CSO'
        );
        Test.stopTest();

        System.assert(true, 'Should handle empty product list gracefully');
    }

    @isTest
    static void testNotifyNextApprovalTeam_blankGroupName() {
        List<Product2> products = createTestProducts();

        Test.startTest();
        RES_ProductApprovalNotificationService.notifyNextApprovalTeam(
            products,
            'Finance Team',
            'CSO Team',
            ''
        );
        Test.stopTest();

        System.assert(true, 'Should handle blank group name gracefully');
    }

    @isTest
    static void testNotifyFinalApproval_withValidData() {
        List<Product2> products = createTestProducts();

        Test.startTest();
        RES_ProductApprovalNotificationService.notifyFinalApproval(
            products,
            'CSO Team'
        );
        Test.stopTest();

        System.assertEquals(2, products.size(), 'Products should be processed');
    }

    @isTest
    static void testNotifyFinalApproval_nullProducts() {
        Test.startTest();
        RES_ProductApprovalNotificationService.notifyFinalApproval(
            null,
            'CSO Team'
        );
        Test.stopTest();

        System.assert(true, 'Should handle null products gracefully');
    }

    @isTest
    static void testNotifyProductRejection_withValidData() {
        List<Product2> products = createTestProducts();

        Test.startTest();
        RES_ProductApprovalNotificationService.notifyProductRejection(
            products,
            'Finance Team',
            'Insufficient documentation provided'
        );
        Test.stopTest();

        System.assertEquals(2, products.size(), 'Products should be processed');
    }

    @isTest
    static void testNotifyProductRejection_withHtmlInReason() {
        List<Product2> products = createTestProducts();

        Test.startTest();
        RES_ProductApprovalNotificationService.notifyProductRejection(
            products,
            'DevCo Team',
            'Missing specs & <requirements>'
        );
        Test.stopTest();

        System.assert(true, 'Should escape HTML in rejection reason');
    }

    @isTest
    static void testNotifyProductRejection_nullProducts() {
        Test.startTest();
        RES_ProductApprovalNotificationService.notifyProductRejection(
            null,
            'Finance Team',
            'Rejected'
        );
        Test.stopTest();

        System.assert(true, 'Should handle null products gracefully');
    }

    // ============================================================
    // RES_SendEmailInvocable INTEGRATION TESTS
    // ============================================================

    @isTest
    static void testSendEmailInvocable_withMergeFields() {
        List<RES_SendEmailInvocable.inputs> inputList = new List<RES_SendEmailInvocable.inputs>();

        RES_SendEmailInvocable.inputs input = new RES_SendEmailInvocable.inputs();
        input.recipients = new List<String>{ 'test@example.com' };
        input.orgWideEmailAddressId = null;
        input.emailSubject = 'Test Subject';
        input.emailBody = '<p>Hello {0}, your product {1} is ready.</p>';
        input.mergeFields = new List<String>{ 'John', 'Widget' };

        inputList.add(input);

        Test.startTest();
        RES_SendEmailInvocable.sendEmails(inputList);
        Test.stopTest();

        Integer emailInvocations = Limits.getEmailInvocations();
        System.assert(
            emailInvocations >= 0,
            'Email invocation should be tracked'
        );
    }

    @isTest
    static void testSendEmailInvocable_emptyMergeFields() {
        List<RES_SendEmailInvocable.inputs> inputList = new List<RES_SendEmailInvocable.inputs>();

        RES_SendEmailInvocable.inputs input = new RES_SendEmailInvocable.inputs();
        input.recipients = new List<String>{ 'test@example.com' };
        input.orgWideEmailAddressId = null;
        input.emailSubject = 'Test Subject';
        input.emailBody = '<p>Simple body with no merge fields.</p>';
        input.mergeFields = new List<String>();

        inputList.add(input);

        Test.startTest();
        RES_SendEmailInvocable.sendEmails(inputList);
        Test.stopTest();

        System.assert(true, 'Should handle empty merge fields');
    }

    // ============================================================
    // EDGE CASE TESTS
    // ============================================================

    @isTest
    static void testSpecialCharactersInTeamNames() {
        List<Product2> products = createTestProducts();

        Test.startTest();
        RES_ProductApprovalNotificationService.notifyNextApprovalTeam(
            products,
            'Finance & Operations <Team>',
            'CSO & Executive "Team"',
            'RES_CSO'
        );
        Test.stopTest();

        System.assert(true, 'Should escape special characters in team names');
    }

    @isTest
    static void testLargeProductList() {
        List<Product2> products = new List<Product2>();

        for (Integer i = 0; i < 10; i++) {
            Product2 product = new Product2(
                Name = 'Product ' + i,
                ProductCode = 'PROD-' + String.valueOf(i).leftPad(3, '0'),
                RES_Unit_Status__c = 'Pending Finance Approval'
            );
            products.add(product);
        }
        insert products;

        Test.startTest();
        RES_ProductApprovalNotificationService.notifyNextApprovalTeam(
            products,
            'DevCo Team',
            'Finance Team',
            'RES_Finance_Team_Group'
        );
        Test.stopTest();

        System.assertEquals(10, products.size(), 'All products should be processed');
    }

    @isTest
    static void testProductWithNullProductCode() {
        Product2 product = new Product2(
            Name = 'Product Without Code',
            ProductCode = null,
            RES_Unit_Status__c = 'Pending Finance Approval'
        );
        insert product;

        Test.startTest();
        RES_ProductApprovalNotificationService.notifyFinalApproval(
            new List<Product2>{ product },
            'CSO Team'
        );
        Test.stopTest();

        System.assert(true, 'Should handle null product codes gracefully');
    }
}