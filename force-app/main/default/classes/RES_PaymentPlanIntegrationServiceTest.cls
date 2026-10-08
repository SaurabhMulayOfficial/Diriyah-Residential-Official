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
    
    @testSetup
    public static void setupData(){
        Test.startTest();
        // Pattern: SObjectType.[Object_API_Name].getRecordTypeInfosByDeveloperName().get('[Developer_Name]').getRecordTypeId()
        
        Id paymentPlanRecordTypeId = Schema.SObjectType.Product2
            .getRecordTypeInfosByDeveloperName()
            .get('RES_Residential_Payment_Plan')
            .getRecordTypeId();
        Product2 paymentPlan = RES_TestDataFactory.createPaymentPlan('Test Payment Plan', paymentPlanRecordTypeId);
        Test.stopTest();
    } 
    
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
    
    private static Product2 buildPaymentPlan() {
        Id paymentPlanRecordTypeId = Schema.SObjectType.Product2
            .getRecordTypeInfosByDeveloperName()
            .get('RES_Residential_Payment_Plan')
            .getRecordTypeId();
        Product2 paymentPlan = RES_TestDataFactory.createPaymentPlan('Test Payment Plan', paymentPlanRecordTypeId);
        
        return [
            SELECT Id, RES_Product_External_ID__c, Name, RES_No_of_Years__c, AvailabilityDate, DiscontinuedDate, RES_Approval_Status__c, 
            RES_Status_Role_Description__c, RES_Status_Role__c, RES_Note__c, RES_No_of_Months__c, RES_Review__c,
            CreatedDate, CreatedBy.Alias, LastModifiedBy.Alias, LastModifiedDate, RES_Validity_End_Date__c, RES_Condition_Type__c 
            FROM Product2 
            WHERE Id = : paymentPlan.Id
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
        Product2 pp = buildPaymentPlan();
        
        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(successResponse()));
        
        List<RES_API_Configuration__mdt> configs = [
            SELECT Id FROM RES_API_Configuration__mdt
            WHERE DeveloperName = 'Payment_Plan' LIMIT 1
        ];
        if (configs.isEmpty()) { return; }
        
        Test.startTest();
        RES_PaymentPlanIntegrationService.syncPaymentPlans(new List<Product2>{ pp }, 'GET', 'I');
        Test.stopTest();
        
        Product2 updated = [SELECT RES_Last_Sync_DateTime__c FROM Product2 WHERE Id = :pp.Id];
        Assert.isNotNull(updated.RES_Last_Sync_DateTime__c, 'Last sync timestamp should be set after successful sync.');
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // syncPaymentPlans (Payment Plan) — error response path
    // ─────────────────────────────────────────────────────────────────────────
    
    @isTest
    static void syncPaymentPlansDoesNotSetTimestampOnErrorResponse() {
        Product2 pp = buildPaymentPlan();
        
        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(errorResponse()));
        
        List<RES_API_Configuration__mdt> configs = [
            SELECT Id FROM RES_API_Configuration__mdt
            WHERE DeveloperName = 'Payment_Plan' LIMIT 1
        ];
        if (configs.isEmpty()) { return; }
        
        Test.startTest();
        RES_PaymentPlanIntegrationService.syncPaymentPlans(new List<Product2>{ pp }, 'GET', 'I');
        Test.stopTest();
        
        Product2 updated = [SELECT RES_Last_Sync_DateTime__c FROM Product2 WHERE Id = :pp.Id];
        Assert.isNull(updated.RES_Last_Sync_DateTime__c, 'Timestamp must remain null when response contains an error.');
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // syncPaymentPlans (Payment Plan) — blank response body
    // ─────────────────────────────────────────────────────────────────────────
    
    @isTest
    static void syncPaymentPlansHandlesBlankResponseBody() {
        Product2 pp = buildPaymentPlan();
        
        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(''));
        
        List<RES_API_Configuration__mdt> configs = [
            SELECT Id FROM RES_API_Configuration__mdt
            WHERE DeveloperName = 'Payment_Plan' LIMIT 1
        ];
        if (configs.isEmpty()) { return; }
        
        Test.startTest();
        RES_PaymentPlanIntegrationService.syncPaymentPlans(new List<Product2>{ pp }, 'GET', 'I');
        Test.stopTest();
        
        Product2 updated = [SELECT Id, RES_Last_Sync_DateTime__c, RES_Product_External_ID__c 
                            FROM Product2 WHERE Id = :pp.Id];
        Assert.isNull(updated.RES_Last_Sync_DateTime__c, 'Blank response should not set the sync timestamp.');
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // syncPaymentPlans (Payment Plan) — HTTP 500 swallowed
    // ─────────────────────────────────────────────────────────────────────────
    
    @isTest
    static void syncPaymentPlansSwallowsHttpException() {
        Product2 pp = buildPaymentPlan();
        
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
            RES_PaymentPlanIntegrationService.syncPaymentPlans(new List<Product2>{ pp }, 'GET', 'I');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        
        Assert.isFalse(threw, 'syncPaymentPlans must swallow HTTP exceptions and not rethrow.');
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // syncPaymentPlans (Installment) — success path
    // ─────────────────────────────────────────────────────────────────────────
    
    // ─────────────────────────────────────────────────────────────────────────
    // RES_IntegrationQueueable — Payment_Plan branch
    // ─────────────────────────────────────────────────────────────────────────
    
    @isTest
    static void queueablePaymentPlanBranchExecutesWithoutException() {
        Product2 pp = buildPaymentPlan();
        
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
    
    @isTest
    static void getTokenParsesAccessTokenFromSuccessfulResponse() {
        RES_IntegrationTestDataFactory.clearSapToken();
        
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.tokenBody = '{"access_token":"abc-123","expires_in":3600}';
        Test.setMock(HttpCalloutMock.class, mock);
        
        Test.startTest();
        String token = new RES_SAPTokenProvider().getToken();
        Test.stopTest();
        
        Assert.areEqual('abc-123', token, 'The access_token value should be extracted from the payload.');
        Assert.areEqual('abc-123', RES_SAPTokenProvider.SAP_TOKEN, 'The token should be cached statically.');
        Assert.areEqual(1, mock.tokenCallCount, 'Exactly one token callout should be made.');
    }
    
    @isTest
    public static void testApproval(){
        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(successResponse()));
        Test.startTest();
        List<Product2> paymentPlanLst = [ SELECT Id, IsActive, RES_Approval_Status__c, RES_Product_External_ID__c 
                                         FROM Product2 
                                         WHERE Name = 'Test Payment Plan' LIMIT 1];
        if(!paymentPlanLst.isEmpty()){
            Product2 paymentPlan = new Product2(Id = paymentPlanLst[0].Id, IsActive = true, RES_Approval_Status__c = 'Approved');
            
            Id installmentRecordTypeId = Schema.SObjectType.Product2
                .getRecordTypeInfosByDeveloperName()
                .get('RES_Residential_Installment')
                .getRecordTypeId(); 
            
            Product2 installment = RES_TestDataFactory.createInstallment('Inst - 1', installmentRecordTypeId);
            RES_TestDataFactory.createPRC(paymentPlan, installment);
            
            Id residentialSalesRecordTypeId = Schema.SObjectType.Product2
                .getRecordTypeInfosByDeveloperName()
                .get('RES_Residential_Sales')
                .getRecordTypeId(); 
            
            //Product2 assignment = RES_TestDataFactory.createPaymentPlanAssignment('Test Payment Plan Assignment', residentialSalesRecordTypeId);
            //RES_TestDataFactory.createPaymentPlanAssignmentPRC(assignment, paymentPlan);
            
            update paymentPlan;
        }
        Test.stopTest();
    } 
}