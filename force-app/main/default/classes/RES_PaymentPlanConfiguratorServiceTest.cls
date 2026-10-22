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
            '{"conditionType":"Y002","conditionMonths":0,"percentage":20,"pocPercentage":0,"sequence":1},' +
            '{"conditionType":"Y003","conditionMonths":6,"conditionDays":15,"percentage":50,"pocPercentage":50,"sequence":2},' +
            '{"conditionType":"Y004","conditionMonths":12,"percentage":30,"sequence":3}' +
        ']';
    }

    private static String twoInstallmentsJson(String firstType, Integer firstMonths, String secondType, Integer secondMonths) {
        return '[{"conditionType":"' + firstType + '","conditionMonths":' + firstMonths + ',"percentage":50,"pocPercentage":50,"sequence":1},' +
            '{"conditionType":"' + secondType + '","conditionMonths":' + secondMonths + ',"percentage":50,"pocPercentage":100,"sequence":2}]';
    }

    private static Id insertCatalog(String developmentPhase) {
        ProductCatalog catalog = new ProductCatalog(Name = 'Test Catalog ' + developmentPhase, RES_Development_Phase__c = developmentPhase);
        insert catalog;
        return catalog.Id;
    }

    private static RES_PaymentPlanConfiguratorService.Result createOne(RES_PaymentPlanConfiguratorService.Request req) {
        Test.startTest();
        List<RES_PaymentPlanConfiguratorService.Result> results =
            RES_PaymentPlanConfiguratorService.createPaymentPlan(new List<RES_PaymentPlanConfiguratorService.Request>{ req });
        Test.stopTest();
        return results[0];
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
                   AvailabilityDate, RES_Validity_End_Date__c, RecordType.DeveloperName,
                   RES_No_of_Months__c, RES_Status_Role__c, RES_Status_Role_Description__c
            FROM Product2 WHERE Id = :result.paymentPlanId
        ];
        System.assertEquals(36, plan.RES_No_of_Months__c);
        System.assertEquals('REL', plan.RES_Status_Role__c);
        System.assertEquals('Released', plan.RES_Status_Role_Description__c);
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
            SELECT Id, Name, RES_CIP_Type__c, RES_POC_Percentage__c, RES_Instalment_DueDate__c, RecordType.DeveloperName,
                   RES_Sequence__c, RES_Installment_Percentage__c, RES_Installment_Accumulative_Payments__c
            FROM Product2 WHERE Id IN :childProductIds ORDER BY RES_Sequence__c
        ];
        System.assertEquals(3, installments.size());
        Set<String> installmentNames = new Set<String>();
        for (Product2 installment : installments) {
            System.assertEquals('Installment', installment.RES_CIP_Type__c);
            System.assertEquals('RES_Residential_Installment', installment.RecordType.DeveloperName);
            installmentNames.add(installment.Name);
        }
        System.assertEquals(new Set<String>{ 'Down payment', 'Installments', 'Final Payment' }, installmentNames);

        Decimal expectedAccumulative = 0;
        for (Product2 installment : installments) {
            expectedAccumulative += installment.RES_Installment_Percentage__c;
            System.assertEquals(expectedAccumulative, installment.RES_Installment_Accumulative_Payments__c, 'Accumulative % should be the running total in sequence order');
        }
        System.assertEquals(100, installments[installments.size() - 1].RES_Installment_Accumulative_Payments__c);

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
        req.installmentsJson = '[{"conditionType":"Y002","conditionMonths":0,"percentage":40,"pocPercentage":50,"sequence":1},' +
            '{"conditionType":"Y003","conditionMonths":6,"percentage":40,"pocPercentage":100,"sequence":2}]';

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
    static void testCreatePaymentPlan_MissingInstallmentType_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-003';
        req.installmentsJson = '[{"conditionMonths":0,"percentage":100,"sequence":1}]';

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('Installment Type'), 'Expected installment type error, got: ' + result.message);
    }

    @IsTest
    static void testCreatePaymentPlan_MissingConditionMonths_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-003A';
        req.installmentsJson = '[{"conditionType":"Y002","conditionDays":10,"percentage":100,"sequence":1}]';

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('Condition Months'), 'Expected condition months error, got: ' + result.message);
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
        req.installmentsJson = '[{"conditionType":"Y002","conditionMonths":0,"percentage":50,"pocPercentage":50,"sequence":1},' +
            '{"conditionType":"Y003","conditionMonths":6,"percentage":50,"pocPercentage":100,"sequence":1}]';

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
        badReq.installmentsJson = '[{"conditionType":"Y002","conditionMonths":0,"percentage":10,"pocPercentage":10,"sequence":1}]';

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

    @IsTest
    static void testCreatePaymentPlan_OffPlanDueDate_CalculatedFromValidFrom() {
        Date validFrom = Date.today().addDays(10);
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-COND';
        req.catalogId = insertCatalog('Off-Plan');
        req.validFromDate = validFrom;
        req.validToDate = null;
        req.installmentsJson = '[{"conditionType":"Y002","conditionMonths":2,"conditionDays":5,"dueDate":"2000-01-01","percentage":50,"pocPercentage":10,"sequence":1},' +
            '{"conditionType":"Y004","conditionMonths":36,"percentage":50,"pocPercentage":100,"sequence":2}]';

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(true, result.isSuccess, 'Expected success, got: ' + result.message);
        Product2 first = [SELECT Name, RES_Condition_Type__c, RES_Condition_Months__c, RES_Condition_Days__c, RES_Instalment_DueDate__c FROM Product2 WHERE ProductCode = 'TEST-PP-COND-INST1'];
        System.assertEquals('Down payment', first.Name);
        System.assertEquals('Y002', first.RES_Condition_Type__c);
        System.assertEquals(2, first.RES_Condition_Months__c);
        System.assertEquals(5, first.RES_Condition_Days__c);
        System.assertEquals(validFrom.addMonths(2).addDays(5), first.RES_Instalment_DueDate__c, 'Client due date must be ignored');
        Product2 second = [SELECT RES_Condition_Days__c, RES_Instalment_DueDate__c FROM Product2 WHERE ProductCode = 'TEST-PP-COND-INST2'];
        System.assertEquals(0, second.RES_Condition_Days__c, 'Blank Condition Days defaults to 0');
        System.assertEquals(validFrom.addMonths(36), second.RES_Instalment_DueDate__c);
    }

    @IsTest
    static void testCreatePaymentPlan_OnPlan_StoresConditionsButNoDueDate() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-ON-DUE';
        req.catalogId = insertCatalog('On-Plan');

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(true, result.isSuccess, 'Expected success, got: ' + result.message);
        Product2 second = [SELECT RES_Condition_Months__c, RES_Condition_Days__c, RES_Instalment_DueDate__c FROM Product2 WHERE ProductCode = 'TEST-PP-ON-DUE-INST2'];
        System.assertEquals(6, second.RES_Condition_Months__c);
        System.assertEquals(15, second.RES_Condition_Days__c);
        System.assertEquals(null, second.RES_Instalment_DueDate__c, 'On-Plan due dates are set when the plan is configured on a quote');
    }

    @IsTest
    static void testCreatePaymentPlan_ConditionMonthsBeyondNumberOfYears_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-COND-MAX';
        req.numberOfYears = 2;
        req.installmentsJson = twoInstallmentsJson('Y002', 0, 'Y004', 28);

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('cannot exceed 24 months'), 'Expected years cap error, got: ' + result.message);
    }

    @IsTest
    static void testCreatePaymentPlan_DecimalYears_SetsMonthsAndCap() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-DEC';
        req.numberOfYears = 2.5;
        req.installmentsJson = twoInstallmentsJson('Y002', 0, 'Y004', 30);

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(true, result.isSuccess, 'Expected success, got: ' + result.message);
        Product2 plan = [SELECT RES_No_of_Years__c, RES_No_of_Months__c FROM Product2 WHERE Id = :result.paymentPlanId];
        System.assertEquals(2.5, plan.RES_No_of_Years__c);
        System.assertEquals(30, plan.RES_No_of_Months__c);
    }

    @IsTest
    static void testCreatePaymentPlan_DecimalYearsExceeded_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-DEC-MAX';
        req.numberOfYears = 2.5;
        req.installmentsJson = twoInstallmentsJson('Y002', 0, 'Y004', 31);

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('cannot exceed 30 months'), 'Expected years cap error, got: ' + result.message);
    }

    @IsTest
    static void testMonthsFor_RoundsToNearestMonth() {
        System.assertEquals(null, RES_PaymentPlanConfiguratorService.monthsFor(null));
        System.assertEquals(24, RES_PaymentPlanConfiguratorService.monthsFor(2));
        System.assertEquals(28, RES_PaymentPlanConfiguratorService.monthsFor(2.33));
        System.assertEquals(15, RES_PaymentPlanConfiguratorService.monthsFor(1.25));
    }

    @IsTest
    static void testCreatePaymentPlan_ConditionDaysPastNumberOfYears_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-COND-MAXD';
        req.numberOfYears = 2;
        req.installmentsJson = '[{"conditionType":"Y002","conditionMonths":0,"percentage":50,"sequence":1},' +
            '{"conditionType":"Y004","conditionMonths":24,"conditionDays":1,"percentage":50,"sequence":2}]';

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('cannot exceed 24 months'), 'Expected years cap error, got: ' + result.message);
        System.assert(result.message.contains('24 months, 1 days'), 'Expected the offending months/days in the error, got: ' + result.message);
    }

    @IsTest
    static void testCreatePaymentPlan_ExactlyNumberOfYears_Succeeds() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-COND-EXACT';
        req.numberOfYears = 2;
        req.validFromDate = Date.newInstance(2027, 1, 1);
        req.installmentsJson = '[{"conditionType":"Y002","conditionMonths":0,"percentage":50,"sequence":1},' +
            '{"conditionType":"Y004","conditionMonths":24,"conditionDays":0,"percentage":50,"sequence":2}]';

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(true, result.isSuccess, 'Expected success, got: ' + result.message);
    }

    @IsTest
    static void testCreatePaymentPlan_DaysWithinNumberOfYears_Succeeds() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-COND-DAYSOK';
        req.numberOfYears = 2;
        req.validFromDate = Date.newInstance(2027, 1, 1);
        // 2027-01-01 + 23 months + 31 days = 2029-01-01, exactly the 24-month limit
        req.installmentsJson = '[{"conditionType":"Y002","conditionMonths":0,"percentage":50,"sequence":1},' +
            '{"conditionType":"Y004","conditionMonths":23,"conditionDays":31,"percentage":50,"sequence":2}]';

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(true, result.isSuccess, 'Expected success, got: ' + result.message);
    }

    @IsTest
    static void testCreatePaymentPlan_DaysPushPastNumberOfYears_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-COND-DAYSMAX';
        req.numberOfYears = 2;
        req.validFromDate = Date.newInstance(2027, 1, 1);
        // 2027-01-01 + 23 months + 32 days = 2029-01-02, one day past the 24-month limit
        req.installmentsJson = '[{"conditionType":"Y002","conditionMonths":0,"percentage":50,"sequence":1},' +
            '{"conditionType":"Y004","conditionMonths":23,"conditionDays":32,"percentage":50,"sequence":2}]';

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('cannot exceed 24 months'), 'Expected years cap error, got: ' + result.message);
    }

    @IsTest
    static void testCreatePaymentPlan_OffPlanDueDateEntered_StoresDerivedConditions() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-OFF-DUE';
        req.catalogId = insertCatalog('Off-Plan');
        req.numberOfYears = 2;
        req.validFromDate = Date.newInstance(2027, 1, 31);
        // Due dates as entered on the Off-Plan table, with the months/days the component derives from Valid From
        req.installmentsJson = '[{"conditionType":"Y002","dueDate":"2027-02-28","conditionMonths":1,"conditionDays":0,"percentage":50,"pocPercentage":10,"sequence":1},' +
            '{"conditionType":"Y004","dueDate":"2028-12-15","conditionMonths":22,"conditionDays":15,"percentage":50,"pocPercentage":100,"sequence":2}]';

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(true, result.isSuccess, 'Expected success, got: ' + result.message);
        Product2 first = [SELECT RES_Condition_Months__c, RES_Condition_Days__c, RES_Instalment_DueDate__c FROM Product2 WHERE ProductCode = 'TEST-PP-OFF-DUE-INST1'];
        System.assertEquals(Date.newInstance(2027, 2, 28), first.RES_Instalment_DueDate__c);
        Product2 second = [SELECT RES_Condition_Months__c, RES_Condition_Days__c, RES_Instalment_DueDate__c FROM Product2 WHERE ProductCode = 'TEST-PP-OFF-DUE-INST2'];
        System.assertEquals(22, second.RES_Condition_Months__c);
        System.assertEquals(15, second.RES_Condition_Days__c);
        System.assertEquals(Date.newInstance(2028, 12, 15), second.RES_Instalment_DueDate__c);
    }

    @IsTest
    static void testCreatePaymentPlan_ConditionMonthsGoBackwards_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-COND-ORDER';
        req.installmentsJson = twoInstallmentsJson('Y003', 12, 'Y003', 6);

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('cannot fall before installment 1'), 'Expected ordering error, got: ' + result.message);
    }

    @IsTest
    static void testCreatePaymentPlan_DuplicateConditionTypeAndMonths_FailsAndRollsBack() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-COND-DUP';
        req.installmentsJson = twoInstallmentsJson('Y003', 2, 'Y003', 2);

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('same Installment Type (Installments)'), 'Expected condition error, got: ' + result.message);
        System.assertEquals(0, [SELECT COUNT() FROM Product2 WHERE ProductCode LIKE 'TEST-PP-COND-DUP%']);
    }

    @IsTest
    static void testCreatePaymentPlan_SameMonthsDifferentConditionType_Succeeds() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-COND-DIFF';
        req.installmentsJson = twoInstallmentsJson('Y001', 0, 'Y002', 0);

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(true, result.isSuccess, 'Expected success, got: ' + result.message);
        for (Product2 inst : [SELECT RES_Condition_Type__c, RES_Installment_Payment_Type__c FROM Product2 WHERE ProductCode LIKE 'TEST-PP-COND-DIFF-INST%']) {
            System.assertEquals(inst.RES_Condition_Type__c, inst.RES_Installment_Payment_Type__c, 'Installment Payment Type should mirror the Condition Type code');
        }
    }

    @IsTest
    static void testCreatePaymentPlan_OnPlanWithoutYears_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-ON-NOYRS';
        req.catalogId = insertCatalog('On-Plan');
        req.numberOfYears = null;

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('Number of Years'), 'Expected years error, got: ' + result.message);
    }

    @IsTest
    static void testCreatePaymentPlan_OnPlan_ForcesPocTo100() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-ON';
        req.catalogId = insertCatalog('On-Plan');

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(true, result.isSuccess, 'Expected success, got: ' + result.message);
        for (Product2 inst : [SELECT RES_POC_Percentage__c FROM Product2 WHERE ProductCode LIKE 'TEST-PP-ON-INST%']) {
            System.assertEquals(100, inst.RES_POC_Percentage__c, 'On-Plan installments should have POC fixed at 100%');
        }
    }

    @IsTest
    static void testCreatePaymentPlan_OffPlanMissingPoc_Fails() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-OFF-NOPOC';
        req.catalogId = insertCatalog('Off-Plan');

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(false, result.isSuccess);
        System.assert(result.message.contains('POC %'), 'Expected POC error, got: ' + result.message);
    }

    @IsTest
    static void testCreatePaymentPlan_OffPlanWithPocAndNoYears_Succeeds() {
        RES_PaymentPlanConfiguratorService.Request req = baseRequest();
        req.productCode = 'TEST-PP-OFF';
        req.catalogId = insertCatalog('Off-Plan');
        req.numberOfYears = null;
        req.installmentsJson = '[{"conditionType":"Y002","conditionMonths":0,"percentage":40,"pocPercentage":10,"sequence":1},' +
            '{"conditionType":"Y004","conditionMonths":48,"percentage":60,"pocPercentage":80,"sequence":2}]';

        RES_PaymentPlanConfiguratorService.Result result = createOne(req);

        System.assertEquals(true, result.isSuccess, 'Expected success, got: ' + result.message);
        Product2 first = [SELECT RES_POC_Percentage__c FROM Product2 WHERE ProductCode = 'TEST-PP-OFF-INST1'];
        System.assertEquals(10, first.RES_POC_Percentage__c);
    }
}
