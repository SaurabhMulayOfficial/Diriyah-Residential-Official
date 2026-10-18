@IsTest
private class RES_PaymentPlanPreviewControllerTest {

    private static final String CONTEXT_ID = 'test-context-id';

    @TestSetup
    static void setup() {
        // RES_ProductTrigger enqueues an SAP sync callout, which isn't under test here
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        config.RES_Triggers_Off__c = true;
        upsert config;

        Map<String, Schema.RecordTypeInfo> recordTypes = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName();
        Product2 paymentPlan = RES_TestDataFactory.createPaymentPlan('Preview Test Plan', recordTypes.get(System.Label.RES_Product_Payment_Plan_RT).getRecordTypeId());
        // Factory reuses the same unique External ID for plan and installment
        update new Product2(Id = paymentPlan.Id, RES_Product_External_ID__c = 'PREVIEW-TEST-PP');
        Product2 installment = RES_TestDataFactory.createInstallment('Preview Test Installment', recordTypes.get(System.Label.RES_Product_Installment_RT).getRecordTypeId());
        update new Product2(Id = installment.Id, RES_Condition_Months__c = 2, RES_Condition_Days__c = 10);
        Product2 unit = new Product2(Name = 'Preview Test Unit', IsActive = true, Type = 'Bundle', RES_CIP_Type__c = 'Unit',
            RecordTypeId = recordTypes.get('RES_Residential_Sales').getRecordTypeId());
        insert unit;

        ProductRelatedComponent planToInstallment = RES_TestDataFactory.createPRC(paymentPlan, installment);
        update new ProductRelatedComponent(Id = planToInstallment.Id, RES_Installment_Percentage__c = 100);
        insert new ProductRelatedComponent(
            ParentProductId = unit.Id,
            ChildProductId = paymentPlan.Id,
            ProductRelationshipTypeId = planToInstallment.ProductRelationshipTypeId,
            Quantity = 1,
            QuoteVisibility = 'Always',
            IsDefaultComponent = true
        );
    }

    private static Id productId(String name) {
        return [SELECT Id FROM Product2 WHERE Name = :name LIMIT 1].Id;
    }

    private static Map<String, Object> lineNode(String lineItemId, String path, Id product, String dmlStatus, Object amount) {
        Map<String, Object> node = RES_FakeIndustriesContextProvider.buildLineItemNode(lineItemId, path, product, new List<Object>(), dmlStatus);
        if (amount != null) {
            ((Map<String, Object>) node.get('tagValue')).put('RESInstallmentAmount__c', new Map<String, Object>{ 'tagValue' => amount });
        }
        return node;
    }

    private static void useContext(List<Object> nodes) {
        RES_FakeIndustriesContextProvider fake = new RES_FakeIndustriesContextProvider();
        fake.queryTagsResultToReturn = RES_FakeIndustriesContextProvider.wrapQueryResult('SalesTransactionItem', nodes);
        RES_PaymentPlanPreviewController.contextProvider = fake;
    }

    @IsTest
    static void returnsSelectedPlanInstallmentsWithAmountsAndDueDates() {
        Id unitId = productId('Preview Test Unit');
        Id planId = productId('Preview Test Plan');
        Id installmentId = productId('Preview Test Installment');
        useContext(new List<Object>{
            lineNode('L1', 'L1', unitId, null, null),
            lineNode('L2', 'L1/L2', planId, null, null),
            lineNode('L3', 'L1/L2/L3', installmentId, null, 500000)
        });

        Test.startTest();
        RES_PaymentPlanPreviewController.Preview preview = RES_PaymentPlanPreviewController.getPreview(CONTEXT_ID, unitId);
        Test.stopTest();

        System.assertEquals('Preview Test Plan', preview.planName);
        System.assertEquals(1, preview.installments.size());
        RES_PaymentPlanPreviewController.Installment row = preview.installments[0];
        System.assertEquals(100, row.percentage);
        System.assertEquals(500000, row.amount);
        System.assertEquals(Date.today().addMonths(2).addDays(10), row.dueDate);
        System.assertEquals(true, preview.isPriced);
        System.assertEquals(500000, preview.totalAmount);
        System.assertEquals(100, preview.totalPercentage);
    }

    @IsTest
    static void leavesAmountBlankUntilPriced() {
        Id unitId = productId('Preview Test Unit');
        useContext(new List<Object>{
            lineNode('L1', 'L1', unitId, null, null),
            lineNode('L2', 'L1/L2', productId('Preview Test Plan'), null, null)
        });

        RES_PaymentPlanPreviewController.Preview preview = RES_PaymentPlanPreviewController.getPreview(CONTEXT_ID, unitId);

        System.assertEquals(1, preview.installments.size());
        System.assertEquals(null, preview.installments[0].amount);
        System.assertEquals(false, preview.isPriced);
        System.assertEquals(null, preview.totalAmount);
    }

    @IsTest
    static void returnsNullWhenPlanDeletedOrMissing() {
        Id unitId = productId('Preview Test Unit');
        useContext(new List<Object>{
            lineNode('L1', 'L1', unitId, null, null),
            lineNode('L2', 'L1/L2', productId('Preview Test Plan'), 'DELETED', null)
        });

        System.assertEquals(null, RES_PaymentPlanPreviewController.getPreview(CONTEXT_ID, unitId));
        System.assertEquals(null, RES_PaymentPlanPreviewController.getPreview(null, unitId));
    }

    @IsTest
    static void ignoresPlansSelectedOnOtherUnits() {
        Id unitId = productId('Preview Test Unit');
        useContext(new List<Object>{
            lineNode('L1', 'L1', unitId, null, null),
            lineNode('X1', 'X1', productId('Preview Test Installment'), null, null),
            lineNode('X2', 'X1/X2', productId('Preview Test Plan'), null, null)
        });

        System.assertEquals(null, RES_PaymentPlanPreviewController.getPreview(CONTEXT_ID, unitId));
    }

    @IsTest
    static void wrapsContextFailures() {
        RES_FakeIndustriesContextProvider fake = new RES_FakeIndustriesContextProvider();
        fake.throwOnQueryTags = true;
        RES_PaymentPlanPreviewController.contextProvider = fake;

        try {
            RES_PaymentPlanPreviewController.getPreview(CONTEXT_ID, productId('Preview Test Unit'));
            System.assert(false, 'Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e);
        }
    }
}
