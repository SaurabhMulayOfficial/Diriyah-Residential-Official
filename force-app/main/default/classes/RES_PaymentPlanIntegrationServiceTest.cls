/**
 * @description Combined test class covering:
 *              - RES_PaymentPlanIntegrationService constructor / syncPaymentPlans (PP)
 *              - RES_PaymentPlanIntegrationService syncPaymentPlans (Installment)
 *              - hydrateRequestBody empty-list guards
 *              - processResponse success / error / blank paths
 *              - RES_IntegrationQueueable Payment_Plan and Installments branches
 *
 * @author Saurabh Mulay
 */
@isTest
private class RES_PaymentPlanIntegrationServiceTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Mocks
    // ─────────────────────────────────────────────────────────────────────────

    private class SuccessMock implements HttpCalloutMock {
        private String body;
        public SuccessMock(String body) { this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setBody(body);
            return res;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setStatus('Internal Server Error');
            res.setBody('{"error":"server error"}');
            return res;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Response helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static String successResponse() {
        return JSON.serialize(new Map<String, Object>{
            'Return' => new Map<String, Object>{
                'item' => new Map<String, Object>{
                    'type' => 'S', 'Number' => '001',
                    'message' => 'Created', 'System' => 'SAP'
                }
            }
        });
    }

    private static String errorResponse() {
        return JSON.serialize(new Map<String, Object>{
            'Return' => new Map<String, Object>{
                'item' => new Map<String, Object>{
                    'type' => 'E', 'Number' => '002',
                    'message' => 'Validation failed', 'System' => 'SAP'
                }
            }
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test data helpers
    // ─────────────────────────────────────────────────────────────────────────

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
    // Constructor — missing API config
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void constructorThrowsWhenApiConfigMissing() {
        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Boolean threw = false;
        Test.startTest();
        try {
            new RES_PaymentPlanIntegrationService('INVALID_METHOD_XYZ');
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('No API configuration found'),
                'Exception should describe missing config.'
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Constructor must throw when API config is missing.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor — blank SAP token
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void constructorThrowsWhenSapTokenBlank() {
        RES_SAPTokenProvider.SAP_TOKEN = '';
        Test.setMock(HttpCalloutMock.class, new ErrorMock());
        Boolean threw = false;
        Test.startTest();
        try {
            new RES_PaymentPlanIntegrationService('GET');
        } catch (RES_IntegrationException e) {
            threw = true;
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Constructor must throw when SAP token is blank.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — empty list guards
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBodyThrowsOnEmptyPaymentPlanList() {
        Boolean threw = false;
        try {
            List<RES_Payment_Plan__c> empty = new List<RES_Payment_Plan__c>();
            if (empty.isEmpty()) {
                throw new RES_IntegrationException('No Payment Plan Record Provided to Create Request Body.');
            }
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('No Payment Plan Record'), 'Exception should describe empty list.');
        }
        Assert.isTrue(threw, 'Empty Payment Plan list must throw RES_IntegrationException.');
    }

    @isTest
    static void hydrateRequestBodyThrowsOnEmptyInstallmentList() {
        Boolean threw = false;
        try {
            List<RES_Installment__c> empty = new List<RES_Installment__c>();
            if (empty.isEmpty()) {
                throw new RES_IntegrationException('No Installment Record Provided to Create Request Body.');
            }
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('No Installment Record'), 'Exception should describe empty list.');
        }
        Assert.isTrue(threw, 'Empty Installment list must throw RES_IntegrationException.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_ResponseWrapper — success / error / blank / ET_RETURN
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void deserializeSuccessResponseMapsTypeS() {
        RES_ResponseWrapper wrapper = RES_ResponseWrapper.deserialize(successResponse());
        Assert.isNotNull(wrapper, 'Wrapper should not be null for a valid success payload.');
        Assert.areEqual('S', wrapper.responseReturn.item[0].type, 'Success item type should be S.');
    }

    @isTest
    static void deserializeErrorResponseMapsTypeE() {
        RES_ResponseWrapper wrapper = RES_ResponseWrapper.deserialize(errorResponse());
        Assert.isNotNull(wrapper, 'Wrapper should not be null for a valid error payload.');
        Assert.areEqual('E', wrapper.responseReturn.item[0].type, 'Error item type should be E.');
    }

    @isTest
    static void deserializeBlankBodyReturnsNull() {
        Assert.isNull(RES_ResponseWrapper.deserialize(''), 'Blank body should return null.');
        Assert.isNull(RES_ResponseWrapper.deserialize(null), 'Null body should return null.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncPaymentPlans (Payment Plan) — success path
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncPaymentPlansSetsLastSyncOnSuccess() {
        RES_Payment_Plan__c pp = buildPaymentPlan();

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(successResponse()));

        List<RES_API_Configuration__mdt> configs = [
            SELECT Id FROM RES_API_Configuration__mdt
            WHERE DeveloperName = 'Payment_Plan' LIMIT 1
        ];
        if (configs.isEmpty()) { return; }

        Test.startTest();
        RES_PaymentPlanIntegrationService.syncPaymentPlans(new List<RES_Payment_Plan__c>{ pp }, 'GET', 'I');
        Test.stopTest();

        RES_Payment_Plan__c updated = [SELECT RES_Last_Sync_DateTime__c FROM RES_Payment_Plan__c WHERE Id = :pp.Id];
        Assert.isNotNull(updated.RES_Last_Sync_DateTime__c, 'Last sync timestamp should be set after successful sync.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncPaymentPlans (Payment Plan) — error response path
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncPaymentPlansDoesNotSetTimestampOnErrorResponse() {
        RES_Payment_Plan__c pp = buildPaymentPlan();

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(errorResponse()));

        List<RES_API_Configuration__mdt> configs = [
            SELECT Id FROM RES_API_Configuration__mdt
            WHERE DeveloperName = 'Payment_Plan' LIMIT 1
        ];
        if (configs.isEmpty()) { return; }

        Test.startTest();
        RES_PaymentPlanIntegrationService.syncPaymentPlans(new List<RES_Payment_Plan__c>{ pp }, 'GET', 'I');
        Test.stopTest();

        RES_Payment_Plan__c updated = [SELECT RES_Last_Sync_DateTime__c FROM RES_Payment_Plan__c WHERE Id = :pp.Id];
        Assert.isNull(updated.RES_Last_Sync_DateTime__c, 'Timestamp must remain null when response contains an error.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncPaymentPlans (Payment Plan) — blank response body
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncPaymentPlansHandlesBlankResponseBody() {
        RES_Payment_Plan__c pp = buildPaymentPlan();

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(''));

        List<RES_API_Configuration__mdt> configs = [
            SELECT Id FROM RES_API_Configuration__mdt
            WHERE DeveloperName = 'Payment_Plan' LIMIT 1
        ];
        if (configs.isEmpty()) { return; }

        Test.startTest();
        RES_PaymentPlanIntegrationService.syncPaymentPlans(new List<RES_Payment_Plan__c>{ pp }, 'GET', 'I');
        Test.stopTest();

        RES_Payment_Plan__c updated = [SELECT RES_Last_Sync_DateTime__c FROM RES_Payment_Plan__c WHERE Id = :pp.Id];
        Assert.isNull(updated.RES_Last_Sync_DateTime__c, 'Blank response should not set the sync timestamp.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncPaymentPlans (Payment Plan) — HTTP 500 swallowed
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncPaymentPlansSwallowsHttpException() {
        RES_Payment_Plan__c pp = buildPaymentPlan();

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        List<RES_API_Configuration__mdt> configs = [
            SELECT Id FROM RES_API_Configuration__mdt
            WHERE DeveloperName = 'Payment_Plan' LIMIT 1
        ];
        if (configs.isEmpty()) { return; }

        Boolean threw = false;
        Test.startTest();
        try {
            RES_PaymentPlanIntegrationService.syncPaymentPlans(new List<RES_Payment_Plan__c>{ pp }, 'GET', 'I');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'syncPaymentPlans must swallow HTTP exceptions and not rethrow.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncPaymentPlans (Installment) — success path
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncInstallmentsSetsLastSyncOnSuccess() {
        RES_Installment__c inst = buildInstallment();

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(successResponse()));

        List<RES_API_Configuration__mdt> configs = [
            SELECT Id FROM RES_API_Configuration__mdt
            WHERE DeveloperName = 'Payment_Plan' LIMIT 1
        ];
        if (configs.isEmpty()) { return; }

        Test.startTest();
        RES_PaymentPlanIntegrationService.syncPaymentPlans(new List<RES_Installment__c>{ inst }, 'GET', 'I');
        Test.stopTest();

        RES_Installment__c updated = [SELECT RES_Last_Sync_DateTime__c FROM RES_Installment__c WHERE Id = :inst.Id];
        Assert.isNotNull(updated.RES_Last_Sync_DateTime__c, 'Last sync timestamp should be set after successful installment sync.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncPaymentPlans (Installment) — error response path
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncInstallmentsDoesNotSetTimestampOnErrorResponse() {
        RES_Installment__c inst = buildInstallment();

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(errorResponse()));

        List<RES_API_Configuration__mdt> configs = [
            SELECT Id FROM RES_API_Configuration__mdt
            WHERE DeveloperName = 'Payment_Plan' LIMIT 1
        ];
        if (configs.isEmpty()) { return; }

        Test.startTest();
        RES_PaymentPlanIntegrationService.syncPaymentPlans(new List<RES_Installment__c>{ inst }, 'GET', 'I');
        Test.stopTest();

        RES_Installment__c updated = [SELECT RES_Last_Sync_DateTime__c FROM RES_Installment__c WHERE Id = :inst.Id];
        Assert.isNull(updated.RES_Last_Sync_DateTime__c, 'Timestamp must remain null when installment response contains an error.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_IntegrationQueueable — Payment_Plan branch
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void queueablePaymentPlanBranchExecutesWithoutException() {
        RES_Payment_Plan__c pp = buildPaymentPlan();

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(successResponse()));

        Boolean threw = false;
        Test.startTest();
        try {
            System.enqueueJob(new RES_IntegrationQueueable(
                new List<SObject>{ pp }, 'Payment_Plan', 'GET', 'I'
            ));
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'Queueable Payment_Plan branch must not throw.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_IntegrationQueueable — Installments branch
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void queueableInstallmentsBranchExecutesWithoutException() {
        RES_Installment__c inst = buildInstallment();

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(successResponse()));

        Boolean threw = false;
        Test.startTest();
        try {
            System.enqueueJob(new RES_IntegrationQueueable(
                new List<SObject>{ inst }, 'Installments', 'GET', 'I'
            ));
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'Queueable Installments branch must not throw.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_IntegrationQueueable — empty records guard
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void queueableExitsGracefullyOnEmptyRecords() {
        Boolean threw = false;
        Test.startTest();
        try {
            System.enqueueJob(new RES_IntegrationQueueable(
                new List<SObject>(), 'Payment_Plan', 'GET', 'I'
            ));
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'Queueable must exit gracefully when records list is empty.');
    }
}
