@IsTest
private class RES_PaymentPlanConfiguratorServiceTest {

    @TestSetup
    static void setup() {
        // Standard Pricebook entries aren't needed here (Test.getStandardPricebookId()
        // is used by the service under Test.isRunningTest()), but the Residential Sales
        // pricebook, a One-Time selling model, and the Bundle-to-Bundle-Component
        // ProductRelationshipType must exist for real, matching what's already configured
        // in every real org this flow runs in - none of these are visible to a test context
        // automatically (no SeeAllData), even though they exist as real org data.
        insert new Pricebook2(Name = 'Residential Sales', IsActive = true);
        insert new ProductSellingModel(Name = 'One-Time', SellingModelType = 'OneTime', Status = 'Active');
        insert new ProductRelationshipType(
            Name = 'Bundle to Bundle Component Relationship',
            MainProductRoleCat = 'Bundle',
            AssociatedProductRoleCat = 'BundleComponent'
        );

        // RES_ProductTrigger enqueues an SAP sync queueable once RES_Business_Entity__c is set, which throws in test context (no Named Credential) - unrelated here, so turn triggers off for every test method.
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        config.RES_Triggers_Off__c = true;
        upsert config;
    }

    private static String threeInstallmentsJson() {
        return '[' +
            '{"name":"Installment 1","percentage":20,"pocPercentage":0,"dueDate":"2026-01-15","sequence":1},' +
            '{"name":"Installment 2","percentage":50,"pocPercentage":50,"sequence":2},' +
            '{"name":"Installment 3","percentage":30,"dueDate":"2027-06-01","sequence":3}' +
        ']';
    }

    private static RES_PaymentPlanConfiguratorService.Request baseRequest() {
        RES_PaymentPlanConfiguratorService.Request req = new RES_PaymentPlanConfiguratorService.Request();
        req.planName = 'Test 3-Year Plan';
        req.productCode = 'TEST-PP-001';
        req.numberOfYears = 3;
        req.currencyIsoCode = UserInfo.getDefaultCurrency();
        req.priceOption = 'Option 1';
        req.validFromDate = Date.today();
        req.validToDate = Date.today().addYears(3);
        req.isActive = true;
        req.description = 'Created by test';
        req.installmentsJson = threeInstallmentsJson();
        return req;
    }

    @IsTest
    static void testCreatePaymentPlan_HappyPath_CreatesAllRelatedRecords() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();

        Test.startTest();
        List<RES_PaymentPlanConfiguratorService.Result> results =
            RES_PaymentPlanConfiguratorService.createPaymentPlan(new List<RES_PaymentPlanConfiguratorService.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        RES_PaymentPlanConfiguratorService.Result result = results[0];
        System.assertEquals(true, result.isSuccess, 'Expected success, got: ' + result.message);
        System.assertEquals(3, result.installmentCount);
        System.assertNotEquals(null, result.paymentPlanId);

        Product2 plan = [
            SELECT Id, Type, ConfigureDuringSale, RES_CIP_Type__c, RES_No_of_Years__c, RES_Price_Option__c,
                   AvailabilityDate, RES_Validity_End_Date__c, RecordType.DeveloperName
            FROM Product2 WHERE Id = :result.paymentPlanId
        ];
        System.assertEquals('Bundle', plan.Type);
        System.assertEquals('Allowed', plan.ConfigureDuringSale);
        System.assertEquals('Payment Plan', plan.RES_CIP_Type__c);
        System.assertEquals('Option 1', plan.RES_Price_Option__c);
        System.assertEquals(Date.today(), plan.AvailabilityDate.date());
        System.assertEquals(Date.today().addYears(3), plan.RES_Validity_End_Date__c);
        System.assertEquals('RES_Residential_Payment_Plan', plan.RecordType.DeveloperName);

        List<ProductComponentGroup> groups = [SELECT Id, MinBundleComponents, MaxBundleComponents FROM ProductComponentGroup WHERE ParentProductId = :plan.Id];
        System.assertEquals(1, groups.size());
        System.assertEquals(3, groups[0].MinBundleComponents);
        System.assertEquals(3, groups[0].MaxBundleComponents);

        List<ProductRelatedComponent> components = [
            SELECT Id, ChildProductId, RES_Installment_Percentage__c, IsComponentRequired, QuoteVisibility
            FROM ProductRelatedComponent WHERE ParentProductId = :plan.Id
        ];
        System.assertEquals(3, components.size());
        Decimal totalPct = 0;
        for (ProductRelatedComponent c : components) {
            System.assertEquals(true, c.IsComponentRequired);
            System.assertEquals('Always', c.QuoteVisibility);
            totalPct += c.RES_Installment_Percentage__c;
        }
        System.assertEquals(100, totalPct);

        Set<Id> childProductIds = new Set<Id>();
        for (ProductRelatedComponent c : components) {
            childProductIds.add(c.ChildProductId);
        }

        List<Product2> installments = [
            SELECT Id, Name, RES_CIP_Type__c, RES_POC_Percentage__c, RES_Instalment_DueDate__c, RecordType.DeveloperName
            FROM Product2 WHERE Id IN :childProductIds
        ];
        System.assertEquals(3, installments.size());
        Set<String> installmentNames = new Set<String>();
        for (Product2 installment : installments) {
            System.assertEquals('Installment', installment.RES_CIP_Type__c);
            System.assertEquals('RES_Residential_Installment', installment.RecordType.DeveloperName);
            installmentNames.add(installment.Name);
        }
        System.assertEquals(new Set<String>{ 'Installment 1', 'Installment 2', 'Installment 3' }, installmentNames);

        Set<Id> allProductIds = new Set<Id>{ plan.Id };
        allProductIds.addAll(childProductIds);

        List<PricebookEntry> entries = [SELECT Id, Pricebook2.Name, Product2Id FROM PricebookEntry WHERE Product2Id IN :allProductIds];
        // 2 pricebooks (Standard + Residential Sales) x 4 products (plan + 3 installments)
        System.assertEquals(8, entries.size());

        List<ProductSellingModelOption> sellingOptions = [SELECT Id, Product2Id, IsDefault FROM ProductSellingModelOption WHERE Product2Id IN :allProductIds];
        System.assertEquals(4, sellingOptions.size());
        for (ProductSellingModelOption opt : sellingOptions) {
            System.assertEquals(true, opt.IsDefault);
        }
    }

    @IsTest
    static void testCreatePaymentPlan_PercentagesDoNotSumTo100_FailsAndRollsBack() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-002';
        req.installmentsJson = '[{"name":"Installment 1","percentage":40,"pocPercentage":50,"sequence":1},' +
            '{"name":"Installment 2","percentage":40,"pocPercentage":100,"sequence":2}]';

        Test.startTest();
        List<RES_PaymentPlanConfiguratorService.Result> results =
            RES_PaymentPlanConfiguratorService.createPaymentPlan(new List<RES_PaymentPlanConfiguratorService.Request>{ req });
        Test.stopTest();

        RES_PaymentPlanConfiguratorService.Result result = results[0];
        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('100%'), 'Expected percentage error, got: ' + result.message);
        System.assertEquals(0, [SELECT COUNT() FROM Product2 WHERE ProductCode = 'TEST-PP-002']);
    }

    @IsTest
    static void testCreatePaymentPlan_MissingInstallmentName_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-003';
        req.installmentsJson = '[{"percentage":100,"sequence":1}]';

        Test.startTest();
        List<RES_PaymentPlanConfiguratorService.Result> results =
            RES_PaymentPlanConfiguratorService.createPaymentPlan(new List<RES_PaymentPlanConfiguratorService.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].message.contains('name'), 'Expected name error, got: ' + results[0].message);
    }

    @IsTest
    static void testCreatePaymentPlan_ValidToBeforeValidFrom_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-003B';
        req.validFromDate = Date.today();
        req.validToDate = Date.today().addDays(-1);

        Test.startTest();
        List<RES_PaymentPlanConfiguratorService.Result> results =
            RES_PaymentPlanConfiguratorService.createPaymentPlan(new List<RES_PaymentPlanConfiguratorService.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].message.contains('Valid To'), 'Expected Valid To error, got: ' + results[0].message);
    }

    @IsTest
    static void testCreatePaymentPlan_MissingPriceOption_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-003C';
        req.priceOption = null;

        Test.startTest();
        List<RES_PaymentPlanConfiguratorService.Result> results =
            RES_PaymentPlanConfiguratorService.createPaymentPlan(new List<RES_PaymentPlanConfiguratorService.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].message.contains('Price Option'), 'Expected price option error, got: ' + results[0].message);
    }

    @IsTest
    static void testCreatePaymentPlan_DuplicateProductCode_Fails() {
        insert new Product2(
            Name = 'Existing Product',
            ProductCode = 'TEST-PP-DUP',
            RecordTypeId = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName().get('RES_Residential_Payment_Plan').getRecordTypeId()
        );

        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-DUP';

        Test.startTest();
        List<RES_PaymentPlanConfiguratorService.Result> results =
            RES_PaymentPlanConfiguratorService.createPaymentPlan(new List<RES_PaymentPlanConfiguratorService.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].message.contains('already in use'), 'Expected duplicate code error, got: ' + results[0].message);
    }

    @IsTest
    static void testCreatePaymentPlan_MissingPlanName_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-004';
        req.planName = null;

        Test.startTest();
        List<RES_PaymentPlanConfiguratorService.Result> results =
            RES_PaymentPlanConfiguratorService.createPaymentPlan(new List<RES_PaymentPlanConfiguratorService.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].message.contains('Payment Plan Name'), 'Expected name error, got: ' + results[0].message);
    }

    @IsTest
    static void testCreatePaymentPlan_DuplicateSequence_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-005';
        req.installmentsJson = '[{"name":"Installment 1","percentage":50,"pocPercentage":50,"sequence":1},' +
            '{"name":"Installment 2","percentage":50,"pocPercentage":100,"sequence":1}]';

        Test.startTest();
        List<RES_PaymentPlanConfiguratorService.Result> results =
            RES_PaymentPlanConfiguratorService.createPaymentPlan(new List<RES_PaymentPlanConfiguratorService.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].message.contains('sequence'), 'Expected sequence error, got: ' + results[0].message);
    }

    @IsTest
    static void testCreatePaymentPlan_BulkRequests_AllProcessedIndependently() {
        RES_PaymentPlanConfiguratorService.Request goodReq = baseRequest();
        goodReq.productCode = 'TEST-PP-BULK-GOOD';

        RES_PaymentPlanConfiguratorService.Request badReq = baseRequest();
        badReq.productCode = 'TEST-PP-BULK-BAD';
        badReq.installmentsJson = '[{"name":"Installment 1","percentage":10,"pocPercentage":10,"sequence":1}]';

        Test.startTest();
        List<RES_PaymentPlanConfiguratorService.Result> results = RES_PaymentPlanConfiguratorService.createPaymentPlan(
            new List<RES_PaymentPlanConfiguratorService.Request>{ goodReq, badReq }
        );
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(true, results[0].isSuccess);
        System.assertEquals(false, results[1].isSuccess);
        System.assertEquals(1, [SELECT COUNT() FROM Product2 WHERE ProductCode = 'TEST-PP-BULK-GOOD']);
        System.assertEquals(0, [SELECT COUNT() FROM Product2 WHERE ProductCode = 'TEST-PP-BULK-BAD']);
    }
}