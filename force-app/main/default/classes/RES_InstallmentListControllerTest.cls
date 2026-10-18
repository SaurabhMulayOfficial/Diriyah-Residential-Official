@IsTest
private class RES_InstallmentListControllerTest {

    @TestSetup
    static void setup() {
        // RES_ProductTrigger enqueues an SAP sync callout, which isn't under test here
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        config.RES_Triggers_Off__c = true;
        upsert config;

        Map<String, Schema.RecordTypeInfo> recordTypes = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName();
        Product2 paymentPlan = RES_TestDataFactory.createPaymentPlan('List Test Plan', recordTypes.get(System.Label.RES_Product_Payment_Plan_RT).getRecordTypeId());
        // Factory reuses the same unique External ID for plan and installment
        update new Product2(Id = paymentPlan.Id, RES_Product_External_ID__c = 'LIST-TEST-PP');

        Id installmentRecordTypeId = recordTypes.get(System.Label.RES_Product_Installment_RT).getRecordTypeId();
        Product2 finalPayment = RES_TestDataFactory.createInstallment('List Test Final Payment', installmentRecordTypeId);
        update new Product2(Id = finalPayment.Id, RES_Sequence__c = 2, RES_Installment_Percentage__c = 50,
            RES_Condition_Type__c = 'Y004', RES_Condition_Months__c = 6, RES_Condition_Days__c = 0);
        Product2 downPayment = new Product2(Name = 'List Test Down Payment', IsActive = true, RecordTypeId = installmentRecordTypeId,
            RES_CIP_Type__c = 'Installment', RES_Sequence__c = 1, RES_Installment_Percentage__c = 50, RES_POC_Percentage__c = 100,
            RES_Condition_Type__c = 'Y002', RES_Condition_Months__c = 0, RES_Condition_Days__c = 10,
            RES_Product_External_ID__c = 'LIST-TEST-DP', RES_Installment_Amount__c = 5000, Family = 'Options');
        insert downPayment;

        ProductRelatedComponent finalComponent = RES_TestDataFactory.createPRC(paymentPlan, finalPayment);
        insert new ProductRelatedComponent(
            ParentProductId = paymentPlan.Id,
            ChildProductId = downPayment.Id,
            ProductRelationshipTypeId = finalComponent.ProductRelationshipTypeId,
            Quantity = 1,
            QuoteVisibility = 'Always',
            IsDefaultComponent = true,
            RES_Installment_Percentage__c = 40
        );
    }

    private static Id productId(String name) {
        return [SELECT Id FROM Product2 WHERE Name = :name LIMIT 1].Id;
    }

    @IsTest
    static void returnsInstallmentsInSequenceOrder() {
        Test.startTest();
        List<RES_InstallmentListController.Installment> rows =
            RES_InstallmentListController.getInstallments(productId('List Test Plan'));
        Test.stopTest();

        System.assertEquals(2, rows.size());
        RES_InstallmentListController.Installment first = rows[0];
        System.assertEquals(productId('List Test Down Payment'), first.productId);
        System.assertEquals('Down payment', first.conditionType, 'Condition Type code should resolve to its label');
        System.assertEquals(40, first.percentage, 'Component percentage overrides the installment percentage');
        System.assertEquals(10, first.conditionDays);
        System.assertEquals(5000, first.amount);
        System.assertEquals(true, first.isActive);

        RES_InstallmentListController.Installment second = rows[1];
        System.assertEquals('List Test Final Payment', second.name);
        System.assertEquals('Final Payment', second.conditionType);
        System.assertEquals(50, second.percentage, 'Falls back to the installment percentage');
        System.assertEquals(6, second.conditionMonths);
    }

    @IsTest
    static void returnsEmptyListWithoutInstallments() {
        System.assertEquals(0, RES_InstallmentListController.getInstallments(null).size());
        System.assertEquals(0, RES_InstallmentListController.getInstallments(productId('List Test Final Payment')).size());
    }
}
