/**
 * @description  Test class for RES_IntegrationResponse.
 * @author       Saurabh Mulay
 * @date         23-Sep-2026
 */
@IsTest
private class RES_IntegrationResponseTest {

    // ─── No-arg constructor ──────────────────────────────────────────────────

    @IsTest
    static void testNoArgConstructor_fieldsDefaultToNull() {
        RES_IntegrationResponse response = new RES_IntegrationResponse();

        Assert.isNull(response.statusCode,      'statusCode should default to null');
        Assert.isNull(response.responseBody,    'responseBody should default to null');
        Assert.isNull(response.status,          'status should default to null');
        Assert.isNull(response.responseBodyBlog,'responseBodyBlog should default to null');
        Assert.isNull(response.responseXML,     'responseXML should default to null');
    }

    // ─── Parameterised constructor ───────────────────────────────────────────

    @IsTest
    static void testParameterisedConstructor_setsFields() {
        RES_IntegrationResponse response = new RES_IntegrationResponse(200, '{"success":true}', 'OK');

        Assert.areEqual(200,              response.statusCode,   'statusCode should be 200');
        Assert.areEqual('{"success":true}', response.responseBody, 'responseBody should match');
        Assert.areEqual('OK',             response.status,       'status should be OK');
    }

    @IsTest
    static void testParameterisedConstructor_errorStatus() {
        RES_IntegrationResponse response = new RES_IntegrationResponse(500, 'Internal Server Error', 'ERROR');

        Assert.areEqual(500,                   response.statusCode);
        Assert.areEqual('Internal Server Error', response.responseBody);
        Assert.areEqual('ERROR',               response.status);
    }

    @IsTest
    static void testParameterisedConstructor_nullValues() {
        RES_IntegrationResponse response = new RES_IntegrationResponse(null, null, null);

        Assert.isNull(response.statusCode);
        Assert.isNull(response.responseBody);
        Assert.isNull(response.status);
    }

    // ─── Direct field assignment ──────────────────────────────────────────────

    @IsTest
    static void testDirectFieldAssignment_responseBodyBlog() {
        RES_IntegrationResponse response = new RES_IntegrationResponse();
        Blob testBlob = Blob.valueOf('Test blob content');
        response.responseBodyBlog = testBlob;

        Assert.areEqual(testBlob, response.responseBodyBlog, 'responseBodyBlog should be assignable directly');
    }

    @IsTest
    static void testDirectFieldAssignment_responseXML() {
        RES_IntegrationResponse response = new RES_IntegrationResponse();
        DOM.Document doc = new DOM.Document();
        doc.load('<root><child>value</child></root>');
        response.responseXML = doc;

        Assert.isNotNull(response.responseXML, 'responseXML should be assignable directly');
    }

    @IsTest
    static void testDirectFieldAssignment_statusCode() {
        RES_IntegrationResponse response = new RES_IntegrationResponse();
        response.statusCode = 404;

        Assert.areEqual(404, response.statusCode);
    }
}
