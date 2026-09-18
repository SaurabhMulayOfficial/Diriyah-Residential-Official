/**
 * @description Unit tests for RES_BaseIntegrationCalloutService.
 *
 *              The class under test is virtual and exposes only protected
 *              members, so a concrete stub (CalloutServiceStub) is used to
 *              drive the setters and invoke sendRequest().
 */
@isTest
private class RES_BaseIntegrationCalloutServiceTest {
    private class CalloutServiceStub extends RES_BaseIntegrationCalloutService {

        public RES_IntegrationResponse callSendRequest() {
            return this.sendRequest();
        }

        public void nullifyRequest() {
            this.request = null;
        }

        public void configure(
            String endpoint,
            String method,
            String body,
            Map<String, String> headers,
            Integer maxRetries,
            Integer timeout
        ) {
            this.setEndpoint(endpoint);
            this.setRequestMethod(method);
            this.setBody(body);
            this.setHeaders(headers);
            this.setMaxRetries(maxRetries);
            this.setTimeout(timeout);
        }

        public void configureLogFields(
            String requestName,
            String objectName,
            String calloutService
        ) {
            this.setRequestName(requestName);
            this.setObjectName(objectName);
            this.setCalloutService(calloutService);
        }
    }

    private class StaticResponseMock implements HttpCalloutMock {
        public Integer callCount = 0;
        public HttpRequest lastRequest;

        private Integer statusCode;
        private String status;
        private String body;

        public StaticResponseMock(Integer statusCode, String status, String body) {
            this.statusCode = statusCode;
            this.status = status;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            this.callCount++;
            this.lastRequest = req;

            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setStatus(this.status);
            res.setBody(this.body);
            return res;
        }
    }

    private class FailThenSucceedMock implements HttpCalloutMock {
        public Integer callCount = 0;
        private Integer failuresBeforeSuccess;

        public FailThenSucceedMock(Integer failuresBeforeSuccess) {
            this.failuresBeforeSuccess = failuresBeforeSuccess;
        }

        public HttpResponse respond(HttpRequest req) {
            this.callCount++;

            HttpResponse res = new HttpResponse();
            if (this.callCount <= this.failuresBeforeSuccess) {
                res.setStatusCode(500);
                res.setStatus('Internal Server Error');
                res.setBody('{"error":"transient"}');
            } else {
                res.setStatusCode(200);
                res.setStatus('OK');
                res.setBody('{"result":"ok"}');
            }
            return res;
        }
    }

    private class ThrowingMock implements HttpCalloutMock {
        public Integer callCount = 0;

        public HttpResponse respond(HttpRequest req) {
            this.callCount++;
            throw new CalloutException('Simulated connection failure');
        }
    }

    private static CalloutServiceStub buildStub(Integer maxRetries) {
        CalloutServiceStub stub = new CalloutServiceStub();
        stub.configure(
            'https://example.com/api/v1/resource',
            'POST',
            '{"name":"Test Record"}',
            new Map<String, String>{
                'Content-Type'  => 'application/json',
                'Authorization' => 'Bearer token-123'
            },
            maxRetries,
            20000
        );
        stub.configureLogFields('Create Resource', 'Account', 'RES_ExampleService');
        return stub;
    }

    private static List<RES_Integration_Log__c> queryLogs() {
        return [
            SELECT Id,
                    RES_Error_Message__c,
                    RES_Object_Name__c,
                    RES_Request_Body__c,
                    RES_Request_Method__c,
                    RES_Request_Name__c,
                    RES_Retry_Count__c,
                    RES_Type_of_Failure__c,
                    RES_Headers__c,
                    RES_Callout_Service__c
            FROM RES_Integration_Log__c
        ];
    }

    @isTest
    static void sendRequestReturnsResponseOnSuccess() {
        StaticResponseMock mock = new StaticResponseMock(200, 'OK', '{"id":"001"}');
        Test.setMock(HttpCalloutMock.class, mock);

        CalloutServiceStub stub = buildStub(3);

        Test.startTest();
        RES_IntegrationResponse response = stub.callSendRequest();
        Test.stopTest();

        Assert.isNotNull(response, 'A response should be returned for a 2xx status.');
        Assert.areEqual(200, response.statusCode, 'Status code should be mapped onto the wrapper.');
        Assert.areEqual('OK', response.status, 'Status text should be mapped onto the wrapper.');
        Assert.areEqual('{"id":"001"}', response.responseBody, 'Body should be mapped onto the wrapper.');
        Assert.areEqual(1, mock.callCount, 'A successful call must not be retried.');
        Assert.areEqual(0, queryLogs().size(), 'No failure log should be created on success.');
    }

    @isTest
    static void sendRequestAppliesAllRequestSettings() {
        StaticResponseMock mock = new StaticResponseMock(200, 'OK', 'ok');
        Test.setMock(HttpCalloutMock.class, mock);

        CalloutServiceStub stub = buildStub(1);

        Test.startTest();
        stub.callSendRequest();
        Test.stopTest();

        HttpRequest sent = mock.lastRequest;
        Assert.isNotNull(sent, 'The mock should have captured the outbound request.');
        Assert.areEqual('https://example.com/api/v1/resource', sent.getEndpoint(), 'Endpoint should be applied.');
        Assert.areEqual('POST', sent.getMethod(), 'Request method should be applied.');
        Assert.areEqual('{"name":"Test Record"}', sent.getBody(), 'Request body should be applied.');
        Assert.areEqual('application/json', sent.getHeader('Content-Type'), 'Headers should be applied.');
        Assert.areEqual('Bearer token-123', sent.getHeader('Authorization'), 'Headers should be applied.');
    }

    @isTest
    static void sendRequestSucceedsAfterTransientFailures() {
        FailThenSucceedMock mock = new FailThenSucceedMock(2);
        Test.setMock(HttpCalloutMock.class, mock);

        CalloutServiceStub stub = buildStub(5);

        Test.startTest();
        RES_IntegrationResponse response = stub.callSendRequest();
        Test.stopTest();

        Assert.isNotNull(response, 'A response should be returned once an attempt succeeds.');
        Assert.areEqual(200, response.statusCode, 'The successful attempt should be returned.');
        Assert.areEqual(3, mock.callCount, 'The loop should stop on the first success.');
        Assert.areEqual(0, queryLogs().size(), 'Recovered retries should not be logged as failures.');
    }


    @isTest
    static void statusCode399IsTreatedAsSuccess() {
        Test.setMock(HttpCalloutMock.class, new StaticResponseMock(399, 'Redirect', 'body'));

        CalloutServiceStub stub = buildStub(2);

        Test.startTest();
        RES_IntegrationResponse response = stub.callSendRequest();
        Test.stopTest();

        Assert.isNotNull(response, 'Status codes below 400 are handled as success.');
        Assert.areEqual(399, response.statusCode, 'The response wrapper should carry the raw status code.');
    }

    @isTest
    static void statusCode400IsTreatedAsFailure() {
        Test.setMock(HttpCalloutMock.class, new StaticResponseMock(400, 'Bad Request', 'invalid'));

        CalloutServiceStub stub = buildStub(1);

        Test.startTest();
        RES_IntegrationResponse response = stub.callSendRequest();
        Test.stopTest();

        Assert.isNull(response, 'A 400 response should not be returned to the caller.');
        Assert.areEqual(1, queryLogs().size(), 'A 400 response should produce a failure log.');
    }

    @isTest
    static void clientSideFailureExhaustsRetriesAndLogs() {
        StaticResponseMock mock = new StaticResponseMock(404, 'Not Found', '{"error":"not found"}');
        Test.setMock(HttpCalloutMock.class, mock);

        CalloutServiceStub stub = buildStub(3);

        Test.startTest();
        RES_IntegrationResponse response = stub.callSendRequest();
        Test.stopTest();

        Assert.isNull(response, 'Permanent failures return null.');
        Assert.areEqual(3, mock.callCount, 'All configured retries should be attempted.');

        List<RES_Integration_Log__c> logs = queryLogs();
        Assert.areEqual(1, logs.size(), 'Exactly one failure log should be created.');

        RES_Integration_Log__c log = logs[0];
        Assert.areEqual('Client Side', log.RES_Type_of_Failure__c, '4xx responses are client side failures.');
        Assert.areEqual('{"error":"not found"}', log.RES_Error_Message__c, 'Response body should be logged.');
        Assert.areEqual('Account', log.RES_Object_Name__c, 'Object name should be logged.');
        Assert.areEqual('{"name":"Test Record"}', log.RES_Request_Body__c, 'Request body should be logged.');
        Assert.areEqual('POST', log.RES_Request_Method__c, 'Request method should be logged.');
        Assert.areEqual('Create Resource', log.RES_Request_Name__c, 'Request name should be logged.');
        Assert.areEqual('RES_ExampleService', log.RES_Callout_Service__c, 'Callout service should be logged.');
        Assert.areEqual(0, log.RES_Retry_Count__c, 'Retry count is hard coded to zero by the service.');
        Assert.isNotNull(log.RES_Headers__c, 'Headers should be serialised onto the log.');

        Map<String, Object> loggedHeaders =
            (Map<String, Object>) JSON.deserializeUntyped(log.RES_Headers__c);
        Assert.areEqual('application/json', loggedHeaders.get('Content-Type'), 'Headers should round trip.');
    }

    @isTest
    static void serverSideFailureIsClassifiedCorrectly() {
        Test.setMock(HttpCalloutMock.class, new StaticResponseMock(503, 'Service Unavailable', 'down'));

        CalloutServiceStub stub = buildStub(2);

        Test.startTest();
        RES_IntegrationResponse response = stub.callSendRequest();
        Test.stopTest();

        Assert.isNull(response, 'Permanent failures return null.');

        List<RES_Integration_Log__c> logs = queryLogs();
        Assert.areEqual(1, logs.size(), 'A failure log should be created.');
        Assert.areEqual('Server Side', logs[0].RES_Type_of_Failure__c, '5xx responses are server side failures.');
    }

    @isTest
    static void statusCode500IsServerSideAnd499IsClientSide() {
        Test.setMock(HttpCalloutMock.class, new StaticResponseMock(500, 'Internal Server Error', 'boom'));

        CalloutServiceStub stub = buildStub(1);

        Test.startTest();
        stub.callSendRequest();
        Test.stopTest();

        Assert.areEqual(
            'Server Side',
            queryLogs()[0].RES_Type_of_Failure__c,
            '500 is the lower boundary of the server side range.'
        );
    }

    @isTest
    static void calloutExceptionIsSwallowedAndReturnsNull() {
        ThrowingMock mock = new ThrowingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        CalloutServiceStub stub = buildStub(3);

        Test.startTest();
        RES_IntegrationResponse response = stub.callSendRequest();
        Test.stopTest();

        Assert.isNull(response, 'An exception on every attempt returns null.');
        Assert.areEqual(3, mock.callCount, 'Every retry should still be attempted after an exception.');
        Assert.areEqual(
            0,
            queryLogs().size(),
            'Current behaviour: no log is written when every attempt throws, because no response exists.'
        );
    }

    @isTest
    static void nullRequestReturnsNullWithoutCallout() {
        StaticResponseMock mock = new StaticResponseMock(200, 'OK', 'ok');
        Test.setMock(HttpCalloutMock.class, mock);

        CalloutServiceStub stub = new CalloutServiceStub();
        stub.nullifyRequest();

        Test.startTest();
        RES_IntegrationResponse response = stub.callSendRequest();
        Test.stopTest();

        Assert.isNull(response, 'A null request should short circuit.');
        Assert.areEqual(0, mock.callCount, 'No callout should be attempted.');
    }

    @isTest
    static void nullMaxRetriesReturnsNullWithoutCallout() {
        StaticResponseMock mock = new StaticResponseMock(200, 'OK', 'ok');
        Test.setMock(HttpCalloutMock.class, mock);

        CalloutServiceStub stub = buildStub(null);

        Test.startTest();
        RES_IntegrationResponse response = stub.callSendRequest();
        Test.stopTest();

        Assert.isNull(response, 'A null retry count should short circuit.');
        Assert.areEqual(0, mock.callCount, 'No callout should be attempted.');
    }

    @isTest
    static void zeroMaxRetriesPerformsNoCallout() {
        StaticResponseMock mock = new StaticResponseMock(200, 'OK', 'ok');
        Test.setMock(HttpCalloutMock.class, mock);

        CalloutServiceStub stub = buildStub(0);

        Test.startTest();
        RES_IntegrationResponse response = stub.callSendRequest();
        Test.stopTest();

        Assert.isNull(response, 'Zero retries means the loop never runs.');
        Assert.areEqual(0, mock.callCount, 'No callout should be attempted.');
        Assert.areEqual(0, queryLogs().size(), 'No log should be created when nothing was sent.');
    }

    @isTest
    static void nullHeaderEntriesAreSkipped() {
        StaticResponseMock mock = new StaticResponseMock(200, 'OK', 'ok');
        Test.setMock(HttpCalloutMock.class, mock);

        Map<String, String> headers = new Map<String, String>{
            'Accept'       => 'application/json',
            'X-Null-Value' => null,
            null           => 'orphaned-value'
        };

        CalloutServiceStub stub = new CalloutServiceStub();
        stub.configure('https://example.com/api', 'GET', null, headers, 1, 10000);

        Test.startTest();
        RES_IntegrationResponse response = stub.callSendRequest();
        Test.stopTest();

        Assert.isNotNull(response, 'Null header entries should not break the callout.');
        Assert.areEqual('application/json', mock.lastRequest.getHeader('Accept'), 'Valid headers still apply.');
        Assert.areEqual(1, mock.callCount, 'The callout should still be attempted once.');
    }

    @isTest
    static void emptyBodyAndNullOptionalsAreHandled() {
        StaticResponseMock mock = new StaticResponseMock(200, 'OK', 'ok');
        Test.setMock(HttpCalloutMock.class, mock);

        CalloutServiceStub stub = new CalloutServiceStub();
        // No headers, empty body, no timeout.
        stub.configure('https://example.com/api', 'GET', '', null, 1, null);

        Test.startTest();
        RES_IntegrationResponse response = stub.callSendRequest();
        Test.stopTest();

        Assert.isNotNull(response, 'A minimally configured request should still execute.');
        Assert.areEqual('', mock.lastRequest.getBody(), 'An empty body should not be set on the request.');
    }

    @isTest
    static void settersPopulateTheRequestUsedForLogging() {
        Test.setMock(HttpCalloutMock.class, new StaticResponseMock(422, 'Unprocessable', 'validation failed'));

        CalloutServiceStub stub = new CalloutServiceStub();
        stub.configure(
            'https://example.com/patch',
            'PATCH',
            '{"field":"value"}',
            new Map<String, String>{ 'X-Custom' => 'abc' },
            1,
            5000
        );
        stub.configureLogFields('Patch Resource', 'Contact', 'RES_PatchService');

        Test.startTest();
        stub.callSendRequest();
        Test.stopTest();

        RES_Integration_Log__c log = queryLogs()[0];
        Assert.areEqual('PATCH', log.RES_Request_Method__c, 'setRequestMethod should be reflected on the log.');
        Assert.areEqual('Patch Resource', log.RES_Request_Name__c, 'setRequestName should be reflected on the log.');
        Assert.areEqual('Contact', log.RES_Object_Name__c, 'setObjectName should be reflected on the log.');
        Assert.areEqual('RES_PatchService', log.RES_Callout_Service__c, 'setCalloutService should be reflected.');
        Assert.areEqual('{"field":"value"}', log.RES_Request_Body__c, 'setBody should be reflected on the log.');
        Assert.areEqual('{"X-Custom":"abc"}', log.RES_Headers__c, 'setHeaders should be serialised onto the log.');
    }
}