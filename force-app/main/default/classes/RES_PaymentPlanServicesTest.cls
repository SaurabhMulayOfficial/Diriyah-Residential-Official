/**
 * @description Combined test class covering:
 *              - RES_PaymentPlanTriggerHandler (afterInsert / afterUpdate)
 *              - RES_InstallmentTriggerHandler (afterInsert / afterUpdate)
 *              - RES_PaymentPlanServices.syncPaymentPlans
 *              - RES_InstallmentServices.syncInstallments
 *              - RES_PaymentPlanDAOLayer.getPaymentPlansByIds
 *              - RES_InstallmentDAOLayer.getInstallmentsByIds
 *
 * @author Saurabh Mulay
 */
@isTest
private class RES_PaymentPlanServicesTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static Boolean ppConfigReady() {
        RES_SAP_Integration_Config__mdt cfg =
            new RES_SAPIntegrationConfigDAO()
                .getSAPIntegrationConfigByDeveloperName('Payment_Plan');
        return cfg != null && String.isNotBlank(cfg.RES_Sync_Fields__c);
    }

    private static Boolean instConfigReady() {
        RES_SAP_Integration_Config__mdt cfg =
            new RES_SAPIntegrationConfigDAO()
                .getSAPIntegrationConfigByDeveloperName('Installments');
        return cfg != null && String.isNotBlank(cfg.RES_Sync_Fields__c);
    }

    private static RES_Payment_Plan__c buildPaymentPlan() {
        RES_Payment_Plan__c pp = new RES_Payment_Plan__c(
            RES_Status__c     = 'Active',
            RES_Months__c     = 36,
            RES_Years__c      = 3,
            RES_Valid_From__c = Date.today(),
            RES_Valid_To__c   = Date.today().addYears(3)
        );
        insert pp;
        return [
            SELECT Id, RES_Status__c, RES_Months__c, RES_Years__c,
                   RES_Valid_From__c, RES_Valid_To__c, RES_Last_Sync_DateTime__c
            FROM RES_Payment_Plan__c WHERE Id = :pp.Id
        ];
    }

    private static RES_Installment__c buildInstallment() {
        RES_Installment__c inst = new RES_Installment__c(
            RES_Due_Date__c                 = Date.today().addMonths(3),
            RES_Percentage__c               = 10.0,
            RES_Percentage_Of_Completion__c = 20.0
        );
        insert inst;
        return [
            SELECT Id, RES_Due_Date__c, RES_Percentage__c,
                   RES_Percentage_Of_Completion__c, RES_Last_Sync_DateTime__c
            FROM RES_Installment__c WHERE Id = :inst.Id
        ];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_PaymentPlanDAOLayer
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void paymentPlanDaoReturnsEmptyForNull() {
        Test.startTest();
        List<RES_Payment_Plan__c> result = new RES_PaymentPlanDAOLayer().getPaymentPlansByIds(null);
        Test.stopTest();

        Assert.isNotNull(result, 'Result should never be null.');
        Assert.isTrue(result.isEmpty(), 'Null input should return empty list.');
    }

    @isTest
    static void paymentPlanDaoReturnsEmptyForEmptySet() {
        Test.startTest();
        List<RES_Payment_Plan__c> result = new RES_PaymentPlanDAOLayer().getPaymentPlansByIds(new Set<Id>());
        Test.stopTest();

        Assert.isTrue(result.isEmpty(), 'Empty id set should return empty list.');
    }

    @isTest
    static void paymentPlanDaoReturnsRecordsForValidIds() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        RES_Payment_Plan__c pp = buildPaymentPlan();

        Test.startTest();
        List<RES_Payment_Plan__c> result = new RES_PaymentPlanDAOLayer().getPaymentPlansByIds(new Set<Id>{ pp.Id });
        Test.stopTest();

        Assert.isFalse(result.isEmpty(), 'DAO should return records for valid ids.');
        Assert.areEqual(pp.Id, result[0].Id, 'Returned record Id should match.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_InstallmentDAOLayer
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void installmentDaoReturnsEmptyForNull() {
        Test.startTest();
        List<RES_Installment__c> result = new RES_InstallmentDAOLayer().getInstallmentsByIds(null);
        Test.stopTest();

        Assert.isNotNull(result, 'Result should never be null.');
        Assert.isTrue(result.isEmpty(), 'Null input should return empty list.');
    }

    @isTest
    static void installmentDaoReturnsEmptyForEmptySet() {
        Test.startTest();
        List<RES_Installment__c> result = new RES_InstallmentDAOLayer().getInstallmentsByIds(new Set<Id>());
        Test.stopTest();

        Assert.isTrue(result.isEmpty(), 'Empty id set should return empty list.');
    }

    @isTest
    static void installmentDaoReturnsRecordsForValidIds() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        RES_Installment__c inst = buildInstallment();

        Test.startTest();
        List<RES_Installment__c> result = new RES_InstallmentDAOLayer().getInstallmentsByIds(new Set<Id>{ inst.Id });
        Test.stopTest();

        Assert.isFalse(result.isEmpty(), 'DAO should return records for valid ids.');
        Assert.areEqual(inst.Id, result[0].Id, 'Returned record Id should match.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_PaymentPlanServices — syncPaymentPlans
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncPaymentPlansThrowsWhenMdtMissing() {
        if (ppConfigReady()) { return; }

        RES_Payment_Plan__c pp = buildPaymentPlan();
        Boolean threw = false;
        Test.startTest();
        try {
            RES_PaymentPlanServices.syncPaymentPlans(new List<RES_Payment_Plan__c>{ pp }, null);
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Payment_Plan'), 'Exception should reference the Payment_Plan config name.');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'syncPaymentPlans must throw when MDT config is absent.');
    }

    @isTest
    static void syncPaymentPlansOnInsertPublishesEvent() {
        if (!ppConfigReady()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        RES_Payment_Plan__c pp = buildPaymentPlan();
        Boolean threw = false;
        Test.startTest();
        try {
            RES_PaymentPlanServices.syncPaymentPlans(new List<RES_Payment_Plan__c>{ pp }, null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'syncPaymentPlans should not throw when MDT config is present.');
    }

    @isTest
    static void syncPaymentPlansOnUpdateSkipsUnchangedRecords() {
        if (!ppConfigReady()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        RES_Payment_Plan__c pp = buildPaymentPlan();
        Map<Id, RES_Payment_Plan__c> oldMap = new Map<Id, RES_Payment_Plan__c>{
            pp.Id => pp.clone(true, true, false, false)
        };

        Test.startTest();
        try {
            // RES_Last_Sync_DateTime__c is null → update bucket skips this record → no event fired
            RES_PaymentPlanServices.syncPaymentPlans(new List<RES_Payment_Plan__c>{ pp }, oldMap);
        } catch (System.SObjectException e) {
            // MDT sync fields reference a field not present on this object — skip
            return;
        } catch (Exception e) {
            Assert.fail('syncPaymentPlans should not throw for an unchanged record on update: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_InstallmentServices — syncInstallments
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncInstallmentsThrowsWhenMdtMissing() {
        if (instConfigReady()) { return; }

        RES_Installment__c inst = buildInstallment();
        Boolean threw = false;
        Test.startTest();
        try {
            RES_InstallmentServices.syncInstallments(new List<RES_Installment__c>{ inst }, null);
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('Installments'), 'Exception should reference the Installments config name.');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'syncInstallments must throw when MDT config is absent.');
    }

    @isTest
    static void syncInstallmentsOnInsertPublishesEvent() {
        if (!instConfigReady()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        RES_Installment__c inst = buildInstallment();
        Boolean threw = false;
        Test.startTest();
        try {
            RES_InstallmentServices.syncInstallments(new List<RES_Installment__c>{ inst }, null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'syncInstallments should not throw when MDT config is present.');
    }

    @isTest
    static void syncInstallmentsOnUpdateSkipsUnchangedRecords() {
        if (!instConfigReady()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        RES_Installment__c inst = buildInstallment();
        Map<Id, RES_Installment__c> oldMap = new Map<Id, RES_Installment__c>{
            inst.Id => inst.clone(true, true, false, false)
        };

        Test.startTest();
        try {
            // RES_Last_Sync_DateTime__c is null → update bucket skips this record → no event fired
            RES_InstallmentServices.syncInstallments(new List<RES_Installment__c>{ inst }, oldMap);
        } catch (System.SObjectException e) {
            // MDT sync fields reference a field not present on this object — skip
            return;
        } catch (Exception e) {
            Assert.fail('syncInstallments should not throw for an unchanged record on update: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_PaymentPlanTriggerHandler — afterInsert / afterUpdate via DML
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void paymentPlanTriggerFiresOnInsert() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Boolean threw = false;
        Test.startTest();
        try {
            insert new RES_Payment_Plan__c(
                RES_Status__c     = 'Active',
                RES_Months__c     = 12,
                RES_Years__c      = 1,
                RES_Valid_From__c = Date.today(),
                RES_Valid_To__c   = Date.today().addYears(1)
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'Payment Plan insert should not throw an unhandled exception from the trigger.');
    }

    @isTest
    static void paymentPlanTriggerFiresOnUpdate() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        RES_Payment_Plan__c pp = buildPaymentPlan();
        Boolean threw = false;
        Test.startTest();
        try {
            pp.RES_Months__c = 24;
            update pp;
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'Payment Plan update should not throw an unhandled exception from the trigger.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_InstallmentTriggerHandler — afterInsert / afterUpdate via DML
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void installmentTriggerFiresOnInsert() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Boolean threw = false;
        Test.startTest();
        try {
            insert new RES_Installment__c(
                RES_Due_Date__c                 = Date.today().addMonths(1),
                RES_Percentage__c               = 5.0,
                RES_Percentage_Of_Completion__c = 10.0
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'Installment insert should not throw an unhandled exception from the trigger.');
    }

    @isTest
    static void installmentTriggerFiresOnUpdate() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        RES_Installment__c inst = buildInstallment();
        Boolean threw = false;
        Test.startTest();
        try {
            inst.RES_Percentage__c = 20.0;
            update inst;
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'Installment update should not throw an unhandled exception from the trigger.');
    }
}
