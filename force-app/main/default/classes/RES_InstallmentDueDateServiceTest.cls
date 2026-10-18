@IsTest
private class RES_InstallmentDueDateServiceTest {

    private static final Date VALID_FROM = Date.today().addDays(-20);

    @TestSetup
    static void setup() {
        // RES_ProductTrigger enqueues an SAP sync callout, which isn't under test here
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        config.RES_Triggers_Off__c = true;
        upsert config;

        Map<String, Schema.RecordTypeInfo> recordTypes = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName();
        Id planRecordTypeId = recordTypes.get(System.Label.RES_Product_Payment_Plan_RT).getRecordTypeId();
        Id installmentRecordTypeId = recordTypes.get(System.Label.RES_Product_Installment_RT).getRecordTypeId();
        Id relationshipTypeId;
        for (String phase : new List<String>{ 'On-Plan', 'Off-Plan' }) {
            ProductCatalog catalog = new ProductCatalog(Name = 'Due Date ' + phase, RES_Development_Phase__c = phase);
            insert catalog;
            Product2 plan = RES_TestDataFactory.createPaymentPlan('Due Date Plan ' + phase, planRecordTypeId);
            update new Product2(Id = plan.Id, RES_Product_External_ID__c = 'DUE-DATE-PP-' + phase, RES_Business_Entity__c = catalog.Id,
                AvailabilityDate = Datetime.newInstance(VALID_FROM, Time.newInstance(12, 0, 0, 0)));
            Product2 installment = RES_TestDataFactory.createInstallment('Due Date Installment ' + phase, installmentRecordTypeId);
            update new Product2(Id = installment.Id, RES_Product_External_ID__c = 'DUE-DATE-INST-' + phase, RES_Condition_Months__c = 3,
                RES_Condition_Days__c = 4, RES_Instalment_DueDate__c = phase == 'Off-Plan' ? VALID_FROM.addMonths(3).addDays(4) : null);
            if (relationshipTypeId == null) {
                relationshipTypeId = RES_TestDataFactory.createPRC(plan, installment).ProductRelationshipTypeId;
            } else {
                insert new ProductRelatedComponent(ParentProductId = plan.Id, ChildProductId = installment.Id,
                    ProductRelationshipTypeId = relationshipTypeId, Quantity = 1, QuoteVisibility = 'Always', IsDefaultComponent = true);
            }
        }
    }

    private static Id installmentId(String phase) {
        return [SELECT Id FROM Product2 WHERE Name = :('Due Date Installment ' + phase) LIMIT 1].Id;
    }

    @IsTest
    static void testPopulateQuoteLineDueDates_OnPlanCountsFromConfigurationDate() {
        QuoteLineItem line = new QuoteLineItem(Product2Id = installmentId('On-Plan'));

        RES_InstallmentDueDateService.populateQuoteLineDueDates(new List<QuoteLineItem>{ line });

        System.assertEquals(Date.today().addMonths(3).addDays(4), line.RES_Installment_Due_Date__c);
    }

    @IsTest
    static void testPopulateQuoteLineDueDates_OffPlanUsesFixedDueDate() {
        QuoteLineItem line = new QuoteLineItem(Product2Id = installmentId('Off-Plan'));

        RES_InstallmentDueDateService.populateQuoteLineDueDates(new List<QuoteLineItem>{ line });

        System.assertEquals(VALID_FROM.addMonths(3).addDays(4), line.RES_Installment_Due_Date__c);
    }

    @IsTest
    static void testPopulateQuoteLineDueDates_OffPlanWithoutStoredDateFallsBackToValidFrom() {
        Id offPlanInstallmentId = installmentId('Off-Plan');
        update new Product2(Id = offPlanInstallmentId, RES_Instalment_DueDate__c = null);
        QuoteLineItem line = new QuoteLineItem(Product2Id = offPlanInstallmentId);

        RES_InstallmentDueDateService.populateQuoteLineDueDates(new List<QuoteLineItem>{ line });

        System.assertEquals(VALID_FROM.addMonths(3).addDays(4), line.RES_Installment_Due_Date__c);
    }

    @IsTest
    static void testPopulateQuoteLineDueDates_IgnoresNonInstallmentsAndKeepsExistingDates() {
        Id planId = [SELECT Id FROM Product2 WHERE Name = 'Due Date Plan On-Plan' LIMIT 1].Id;
        QuoteLineItem planLine = new QuoteLineItem(Product2Id = planId);
        QuoteLineItem datedLine = new QuoteLineItem(Product2Id = installmentId('On-Plan'), RES_Installment_Due_Date__c = VALID_FROM);

        RES_InstallmentDueDateService.populateQuoteLineDueDates(new List<QuoteLineItem>{ planLine, datedLine });

        System.assertEquals(null, planLine.RES_Installment_Due_Date__c);
        System.assertEquals(VALID_FROM, datedLine.RES_Installment_Due_Date__c);
    }

    @IsTest
    static void testDueDate_NullWithoutAnchorOrConditions() {
        System.assertEquals(null, RES_InstallmentDueDateService.dueDate(null, 1, 1));
        System.assertEquals(null, RES_InstallmentDueDateService.dueDate(Date.today(), null, null));
        System.assertEquals(Date.today().addDays(5), RES_InstallmentDueDateService.dueDate(Date.today(), null, 5));
    }
}
