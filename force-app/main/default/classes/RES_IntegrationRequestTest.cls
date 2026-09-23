/**
 * @description  Test class for RES_IntegrationRequest.
 * @author       Saurabh Mulay
 * @date         23-Sep-2026
 */
@IsTest
private class RES_IntegrationRequestTest {

    // ─── No-arg constructor ──────────────────────────────────────────────────

    @IsTest
    static void testNoArgConstructor_fieldsDefaultToNull() {
        RES_IntegrationRequest request = new RES_IntegrationRequest();

        Assert.isNull(request.endpoint,       'endpoint should default to null');
        Assert.isNull(request.headers,        'headers should default to null');
        Assert.isNull(request.requestName,    'requestName should default to null');
        Assert.isNull(request.requestMethod,  'requestMethod should default to null');
        Assert.isNull(request.requestBody,    'requestBody should default to null');
        Assert.isNull(request.maxRetries,     'maxRetries should default to null');
        Assert.isNull(request.timeout,        'timeout should default to null');
        Assert.isNull(request.objectName,     'objectName should default to null');
        Assert.isNull(request.calloutService, 'calloutService should default to null');
        Assert.isNull(request.recordId,       'recordId should default to null');
    }

    // ─── Parameterised constructor ───────────────────────────────────────────

    @IsTest
    static void testParameterisedConstructor_setsAllFields() {
        Map<String, String> headers = new Map<String, String>{ 'Authorization' => 'Bearer token123' };

        RES_IntegrationRequest request = new RES_IntegrationRequest(
            'https://api.example.com/resource',
            headers,
            'CreateLead',
            'POST',
            '{"key":"value"}',
            3,
            30000,
            'Lead',
            'LeadCalloutService'
        );

        Assert.areEqual('https://api.example.com/resource', request.endpoint);
        Assert.areEqual(headers,             request.headers);
        Assert.areEqual('CreateLead',        request.requestName);
        Assert.areEqual('POST',              request.requestMethod);
        Assert.areEqual('{"key":"value"}',   request.requestBody);
        Assert.areEqual(3,                   request.maxRetries);
        Assert.areEqual(30000,               request.timeout);
        Assert.areEqual('Lead',              request.objectName);
        Assert.areEqual('LeadCalloutService', request.calloutService);
    }

    @IsTest
    static void testParameterisedConstructor_nullHeaders() {
        RES_IntegrationRequest request = new RES_IntegrationRequest(
            'https://api.example.com',
            null,
            'GetRecord',
            'GET',
            null,
            1,
            10000,
            'Account',
            'AccountService'
        );

        Assert.isNull(request.headers,       'null headers should remain null');
        Assert.isNull(request.requestBody,   'null requestBody should remain null');
        Assert.areEqual('GET',               request.requestMethod);
    }

    @IsTest
    static void testParameterisedConstructor_recordIdDefaultsToNull() {
        RES_IntegrationRequest request = new RES_IntegrationRequest(
            'https://api.example.com', null, 'Op', 'POST', '{}', 0, 5000, 'Contact', 'ContactSvc'
        );

        Assert.isNull(request.recordId, 'recordId is not set by parameterised constructor — should remain null');
    }

    // ─── Direct field assignment ──────────────────────────────────────────────

    @IsTest
    static void testDirectFieldAssignment_recordId() {
        RES_IntegrationRequest request = new RES_IntegrationRequest();
        request.recordId = 'a0B000000000001AAA';

        Assert.areEqual('a0B000000000001AAA', request.recordId);
    }

    @IsTest
    static void testDirectFieldAssignment_headers() {
        RES_IntegrationRequest request = new RES_IntegrationRequest();
        Map<String, String> headers = new Map<String, String>{ 'Content-Type' => 'application/json' };
        request.headers = headers;

        Assert.areEqual('application/json', request.headers.get('Content-Type'));
    }

    @IsTest
    static void testDirectFieldAssignment_maxRetriesAndTimeout() {
        RES_IntegrationRequest request = new RES_IntegrationRequest();
        request.maxRetries = 5;
        request.timeout    = 60000;

        Assert.areEqual(5,     request.maxRetries);
        Assert.areEqual(60000, request.timeout);
    }
}
