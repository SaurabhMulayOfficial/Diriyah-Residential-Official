/**
 * @description Unit tests for RES_SAPTokenProvider.
 *
 *              SAP_TOKEN is a static cache that lives for the duration of a
 *              transaction. Each test method is its own transaction, so the
 *              cache starts empty unless a test seeds it deliberately.
 */
@isTest
private class RES_SAPTokenProviderTest {

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
    static void getTokenUsesCacheAndSkipsCallout() {
        RES_SAPTokenProvider.SAP_TOKEN = 'already-cached-token';

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String token = new RES_SAPTokenProvider().getToken();
        Test.stopTest();

        Assert.areEqual('already-cached-token', token, 'The cached token should be returned as is.');
        Assert.areEqual(0, mock.tokenCallCount, 'A cached token must not trigger a callout.');
    }

    @isTest
    static void getTokenCalledTwiceOnlyCallsOutOnce() {
        RES_IntegrationTestDataFactory.clearSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        RES_SAPTokenProvider provider = new RES_SAPTokenProvider();
        String first = provider.getToken();
        String second = provider.getToken();
        Test.stopTest();

        Assert.areEqual(first, second, 'Both calls should return the same token.');
        Assert.areEqual(1, mock.tokenCallCount, 'The second call should be served from the static cache.');
    }

    @isTest
    static void getTokenReturnsNullWhenAccessTokenKeyIsMissing() {
        RES_IntegrationTestDataFactory.clearSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.tokenBody = '{"token_type":"Bearer","expires_in":3600}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String token = new RES_SAPTokenProvider().getToken();
        Test.stopTest();

        Assert.isNull(token, 'A payload without access_token yields a null token.');
    }

    @isTest
    static void getTokenSwallowsMalformedJson() {
        RES_IntegrationTestDataFactory.clearSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.tokenBody = 'this-is-not-json';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String token = new RES_SAPTokenProvider().getToken();
        Test.stopTest();

        Assert.isTrue(String.isBlank(token), 'A parse failure is caught and leaves the token blank.');
    }

    @isTest
    static void getTokenReturnsEmptyWhenResponseBodyIsNotAnObject() {
        RES_IntegrationTestDataFactory.clearSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.tokenBody = '["unexpected","array"]';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String token = new RES_SAPTokenProvider().getToken();
        Test.stopTest();

        Assert.isTrue(String.isBlank(token), 'A cast failure is caught and leaves the token blank.');
    }

    /**
     * Documents a defect rather than approving it.
     *
     * RES_BaseIntegrationCalloutService.sendRequest() returns null on a
     * permanent failure, and getToken() dereferences response.responseBody
     * on the debug line BEFORE entering its try block. A failing token
     * callout therefore throws an uncaught NullPointerException.
     *
     * Once the debug statement is moved inside the try (or a null guard is
     * added), change this test to assert a blank token instead.
     */
    @isTest
    static void getTokenThrowsNullPointerWhenCalloutFails() {
        RES_IntegrationTestDataFactory.clearSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.tokenStatusCode = 401;
        mock.tokenStatus = 'Unauthorized';
        mock.tokenBody = '{"error":"invalid_client"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Boolean threw = false;
        Test.startTest();
        try {
            new RES_SAPTokenProvider().getToken();
        } catch (NullPointerException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A failed token callout currently produces an unhandled NullPointerException.');
        Assert.areEqual(3, mock.tokenCallCount, 'All three configured retries should be attempted first.');
    }

    @isTest
    static void getTokenThrowsNullPointerWhenEveryAttemptErrors() {
        RES_IntegrationTestDataFactory.clearSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.throwOnToken = true;
        Test.setMock(HttpCalloutMock.class, mock);

        Boolean threw = false;
        Test.startTest();
        try {
            new RES_SAPTokenProvider().getToken();
        } catch (NullPointerException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A connection level failure also reaches the unguarded debug statement.');
    }

    @isTest
    static void constructorConfiguresTokenRequest() {
        RES_IntegrationTestDataFactory.clearSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new RES_SAPTokenProvider().getToken();
        Test.stopTest();

        Assert.areEqual(1, mock.tokenCallCount, 'The configured named credential endpoint should be used.');
    }
}