@IsTest
private class RES_PaymentPlanPreviewControllerTest {

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

    private static String productId(String name) {
        return [SELECT Id FROM Product2 WHERE Name = :name LIMIT 1].Id;
    }

    @IsTest
    static void returnsSelectedPlanInstallments() {
        String unitId = productId('Preview Test Unit');
        List<String> selected = new List<String>{ unitId, productId('Preview Test Plan'), productId('Preview Test Installment') };

        Test.startTest();
        RES_PaymentPlanPreviewController.Preview preview = RES_PaymentPlanPreviewController.getPreview(selected, unitId);
        Test.stopTest();

        System.assertEquals('Preview Test Plan', preview.planName);
        System.assertEquals(1, preview.installments.size());
        RES_PaymentPlanPreviewController.Installment row = preview.installments[0];
        System.assertEquals(100, row.percentage);
        System.assertEquals(100, row.pocPercentage);
        System.assertEquals(Date.today().addMonths(2).addDays(10), row.dueDate);
        System.assertEquals(100, preview.totalPercentage);
        // No attribute-based adjustment exists for this unit, so there is no amount base
        System.assertEquals(null, row.amount);
        System.assertEquals(null, preview.totalAmount);
        System.assertEquals(null, preview.unitValue);
        // No service charge rate configured for this unit
        System.assertEquals(null, preview.serviceCharge);
    }

    @IsTest
    static void returnsNullWithoutSelectedPlan() {
        String unitId = productId('Preview Test Unit');

        System.assertEquals(null, RES_PaymentPlanPreviewController.getPreview(new List<String>{ unitId, 'not-an-id' }, unitId));
        System.assertEquals(null, RES_PaymentPlanPreviewController.getPreview(new List<String>(), unitId));
        System.assertEquals(null, RES_PaymentPlanPreviewController.getPreview(null, null));
    }
}
