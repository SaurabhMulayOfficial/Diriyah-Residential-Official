@IsTest
private class RES_PaymentPlanEmailDetailsInvocableTest {

    @TestSetup
    static void setup() {
        // RES_ProductTrigger enqueues an SAP sync callout, which isn't under test here
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        config.RES_Triggers_Off__c = true;
        upsert config;

        Map<String, Schema.RecordTypeInfo> recordTypes = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName();
        Product2 paymentPlan = RES_TestDataFactory.createPaymentPlan('Email Test <Plan>', recordTypes.get(System.Label.RES_Product_Payment_Plan_RT).getRecordTypeId());
        update new Product2(Id = paymentPlan.Id, RES_Product_External_ID__c = 'S000999', RES_No_of_Years__c = 3);

        Id installmentRecordTypeId = recordTypes.get(System.Label.RES_Product_Installment_RT).getRecordTypeId();
        Product2 installment = RES_TestDataFactory.createInstallment('Email Test Installment', installmentRecordTypeId);
        update new Product2(Id = installment.Id, RES_Product_External_ID__c = 'EMAIL-TEST-I1', RES_Sequence__c = 2,
            RES_Installment_Percentage__c = 70, RES_POC_Percentage__c = 100, RES_Condition_Type__c = 'Y003', RES_Condition_Months__c = 12);
        Product2 downPayment = new Product2(Name = 'Email Test Down Payment', IsActive = true, RecordTypeId = installmentRecordTypeId,
            RES_CIP_Type__c = 'Installment', RES_Sequence__c = 1, RES_Installment_Percentage__c = 30, RES_POC_Percentage__c = 90,
            RES_Condition_Type__c = 'Y002', RES_Condition_Months__c = 0, RES_Product_External_ID__c = 'EMAIL-TEST-DP', Family = 'Options');
        insert downPayment;

        ProductRelatedComponent installmentComponent = RES_TestDataFactory.createPRC(paymentPlan, installment);
        insert new ProductRelatedComponent(
            ParentProductId = paymentPlan.Id,
            ChildProductId = downPayment.Id,
            ProductRelationshipTypeId = installmentComponent.ProductRelationshipTypeId,
            Quantity = 1,
            QuoteVisibility = 'Always',
            IsDefaultComponent = true
        );
    }

    private static RES_PaymentPlanEmailDetailsInvocable.Response run(String recordId) {
        RES_PaymentPlanEmailDetailsInvocable.Request request = new RES_PaymentPlanEmailDetailsInvocable.Request();
        request.recordId = recordId;
        List<RES_PaymentPlanEmailDetailsInvocable.Response> responses =
            RES_PaymentPlanEmailDetailsInvocable.getEmailDetails(new List<RES_PaymentPlanEmailDetailsInvocable.Request>{ request });
        System.assertEquals(1, responses.size(), 'One response per request');
        return responses[0];
    }

    @IsTest
    static void buildsPlanDetailsAndSchedule() {
        Id planId = [SELECT Id FROM Product2 WHERE Name = 'Email Test <Plan>' LIMIT 1].Id;

        Test.startTest();
        RES_PaymentPlanEmailDetailsInvocable.Response response = run(planId);
        Test.stopTest();

        System.assert(response.planDetailsHtml.contains('S000999'), 'Payment Plan ID should be the SAP ID');
        System.assert(response.planDetailsHtml.contains('Email Test &lt;Plan&gt;'), 'Description should be the escaped plan name');
        System.assert(response.planDetailsHtml.contains('3 Years'), 'Duration should come from No of Years');

        Integer downPaymentAt = response.scheduleRowsHtml.indexOf('Down payment');
        Integer installmentAt = response.scheduleRowsHtml.indexOf('Installments');
        System.assert(downPaymentAt > -1 && installmentAt > downPaymentAt, 'Rows should use Condition Type labels in sequence order');
        System.assert(response.scheduleRowsHtml.contains('30.00%') && response.scheduleRowsHtml.contains('90.00%'), 'Down payment percentage and POC');
        System.assert(response.scheduleRowsHtml.contains('>12</td>'), 'Installment months');
    }

    @IsTest
    static void returnsBlankRowsForUnknownOrInvalidIds() {
        Test.startTest();
        RES_PaymentPlanEmailDetailsInvocable.Response invalid = run('not-an-id');
        RES_PaymentPlanEmailDetailsInvocable.Response missing = run(null);
        Test.stopTest();

        System.assertEquals('', invalid.planDetailsHtml, 'Invalid Id should not break the email');
        System.assertEquals('', missing.scheduleRowsHtml, 'Missing Id should not break the email');
    }

    @IsTest
    static void showsPlaceholderWhenPlanHasNoInstallments() {
        System.assert(RES_PaymentPlanEmailDetailsInvocable.buildScheduleRows(new List<RES_InstallmentListController.Installment>())
            .contains('No installments defined.'), 'Empty schedule should render a placeholder row');
    }

    @IsTest
    static void formatsDuration() {
        System.assertEquals('2.5 Years', RES_PaymentPlanEmailDetailsInvocable.formatDuration(2.5, 30));
        System.assertEquals('1 Year', RES_PaymentPlanEmailDetailsInvocable.formatDuration(1, null));
        System.assertEquals('6 Months', RES_PaymentPlanEmailDetailsInvocable.formatDuration(null, 6));
        System.assertEquals(null, RES_PaymentPlanEmailDetailsInvocable.formatDuration(null, null));
    }
}
