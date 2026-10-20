/**
 * @description Base service class providing common functionality for
 *              constructing, executing, and handling external integration
 *              HTTP callouts.
 *
 *              Provides request configuration, header and body handling,
 *              retry processing, response handling, and failure logging
 *              functionality for integration services.
 */

public virtual class RES_BaseIntegrationCalloutService {
    public static final String CALLOUT_REQUEST_TYPE = 'Callout Request';
    // Buffered because DML between the token callout and the main callout raises "uncommitted work pending".
    private static List<RES_Integration_Log__c> pendingRequestLogs = new List<RES_Integration_Log__c>();

    protected RES_IntegrationRequest request;

    public RES_BaseIntegrationCalloutService(){
        this.request = new RES_IntegrationRequest();
    }

    protected void setBody(String body){
        this.request.requestBody = body;
    }

    protected void setHeaders(Map<String, String> headers){
        this.request.headers = headers;
    }

    protected void setEndpoint(String endpoint){
        this.request.endpoint = endpoint;
    }

    protected void setRequestMethod(String requestMethod){
        this.request.requestMethod = requestMethod;
    }

    protected void setRequestName(String requestName){
        this.request.requestName = requestName;
    }

    protected void setMaxRetries(Integer maxRetries){
        this.request.maxRetries = maxRetries;
    }

    protected void setTimeout(Integer timeout){
        this.request.timeout = timeout;
    }

    protected void setObjectName(String objectName){
        this.request.objectName = objectName;
    }

    protected void setCalloutService(String calloutService){
        this.request.calloutService = calloutService;
    }

    protected void setRecordId(String recordId){
        this.request.recordId = recordId;
    }

    public Map<String, String> getHeaders() {
        return request.headers;
    }

    public String getRequestBody() {
        return request.requestBody;
    }

    public Integer getRetryCount() {
        return request.maxRetries;
    }

    public String getRequestMethod() {
        return request.requestMethod;
    }

    protected RES_IntegrationResponse sendRequest(){
        if(request == null){
            return null;
        }

        String endpoint = request.endpoint;
        Map<String, String> headers = request.headers;
        String requestMethod = request.requestMethod;
        String requestBody = request.requestBody;
        Integer maxRetries = request.maxRetries;
        Integer timeout = request.timeout;

        HttpRequest httpRequest = new HttpRequest();
        if(endpoint != null){
            httpRequest.setEndpoint(endpoint);
        }

        if(headers != null){
            for(String key: headers.keySet()){
                if(key != null && headers.get(key) != null){
                    httpRequest.setHeader(key, headers.get(key));
                }
            }
        }

        if(requestBody != null && requestBody.length() > 0){
            httpRequest.setBody(requestBody);
        }

        if(requestMethod != null){
            httpRequest.setMethod(requestMethod);
        }

        if(timeout != null){
            httpRequest.setTimeout(timeout);
        }

        Boolean permanentFailure = false;
        RES_IntegrationResponse res;
        if(maxRetries == null){
            return null;
        }

        logCalloutRequest();
        queueRequestLog();

        for(integer i = 0; i < maxRetries; i++){
            System.debug('Attempting request: ' + i);

            try{
                HttpResponse response = new Http().send(httpRequest);
                if(response != null){
                    Integer statusCode = response.getStatusCode();
                    logCalloutResponse(i + 1, response);
                    res = new RES_integrationResponse();
                    res.responseBody = response.getBody();
                    res.status = response.getStatus();
                    res.statusCode = response.getStatusCode();

                    if(statusCode >= 200 && statusCode < 400){
                        permanentFailure = false;
                        return res;
                    }
                    else{
                        permanentFailure = true;
                    }
                }
            }catch(Exception e){
                System.debug(
                    'Fail to execute the request ' + e.getMessage()
                );
            }
        }

        if(permanentFailure == true){
            if(res != null){
                createFailureLogs(res, request);
            }
        }
        return null;
    }

    // Inserts the buffered request logs; call once after the transaction's last callout.
    public static void flushRequestLogs(){
        if(pendingRequestLogs.isEmpty()){
            return;
        }
        try{
            Database.insert(pendingRequestLogs, false, AccessLevel.SYSTEM_MODE);
        }catch(Exception e){
            System.debug('Fail to create callout request logs ' + e.getMessage());
        }
        pendingRequestLogs.clear();
    }

    @TestVisible
    private static List<RES_Integration_Log__c> getPendingRequestLogs(){
        return pendingRequestLogs;
    }

    private void queueRequestLog(){
        try{
            String headersJson = request.headers != null ? JSON.serialize(maskHeaders(request.headers)) : null;
            pendingRequestLogs.add(new RES_Integration_Log__c(
                RES_Type_of_Failure__c = CALLOUT_REQUEST_TYPE,
                RES_Endpoint__c = request.endpoint != null ? request.endpoint.abbreviate(255) : null,
                RES_Request_Body__c = request.requestBody != null ? request.requestBody.abbreviate(131072) : null,
                RES_Request_Method__c = request.requestMethod,
                RES_Request_Name__c = request.requestName,
                RES_Object_Name__c = request.objectName,
                RES_Callout_Service__c = request.calloutService,
                RES_Record_Id__c = request.recordId,
                RES_Headers__c = headersJson != null ? headersJson.abbreviate(32768) : null
            ));
        }catch(Exception e){
            System.debug('Fail to queue callout request log ' + e.getMessage());
        }
    }

    private static Map<String, String> maskHeaders(Map<String, String> headers){
        Map<String, String> safeHeaders = new Map<String, String>();
        for(String key : headers.keySet()){
            if(key == null){
                continue;
            }
            safeHeaders.put(key, key.equalsIgnoreCase('Authorization') ? '***MASKED***' : headers.get(key));
        }
        return safeHeaders;
    }

    // Search the debug log for [CALLOUT_REQUEST] / [CALLOUT_REQUEST_BODY] / [CALLOUT_RESPONSE]; the body line is the raw payload, ready to copy.
    private void logCalloutRequest(){
        try{
            Map<String, String> safeHeaders = request.headers != null
                ? maskHeaders(request.headers)
                : new Map<String, String>();

            Map<String, Object> entry = new Map<String, Object>{
                'requestName' => request.requestName,
                'calloutService' => request.calloutService,
                'objectName' => request.objectName,
                'recordId' => request.recordId,
                'method' => request.requestMethod,
                'endpoint' => request.endpoint,
                'headers' => safeHeaders
            };
            System.debug(LoggingLevel.INFO, '[CALLOUT_REQUEST] ' + JSON.serialize(entry));
            System.debug(LoggingLevel.INFO, '[CALLOUT_REQUEST_BODY] ' + request.requestBody);
        }catch(Exception e){
            System.debug('Fail to log callout request ' + e.getMessage());
        }
    }

    private void logCalloutResponse(Integer attempt, HttpResponse response){
        try{
            // Token response carries the access_token, so its body is never printed.
            Boolean isTokenCall = this instanceof RES_SAPTokenProvider;
            Map<String, Object> entry = new Map<String, Object>{
                'requestName' => request.requestName,
                'recordId' => request.recordId,
                'attempt' => attempt,
                'statusCode' => response.getStatusCode(),
                'status' => response.getStatus()
            };
            System.debug(LoggingLevel.INFO, '[CALLOUT_RESPONSE] ' + JSON.serialize(entry));
            System.debug(LoggingLevel.INFO, '[CALLOUT_RESPONSE_BODY] ' + (isTokenCall ? '***MASKED***' : response.getBody()));
        }catch(Exception e){
            System.debug('Fail to log callout response ' + e.getMessage());
        }
    }


    private void createFailureLogs(
        RES_IntegrationResponse response,
        RES_IntegrationRequest request
    ){

        try{
            if(response == null || request == null){
                return;
            }

            String failureType = 'Client Side';
            if(
                response.statusCode != null &&
                response.statusCode >= 500 &&
                response.statusCode < 600
            ){
                failureType = 'Server Side';
            }

            RES_Integration_Log__c log = new RES_Integration_Log__c(
                RES_Error_Message__c = response.responseBody,
                RES_Object_Name__c = request.objectName,
                RES_Request_Body__c = request.requestBody,
                RES_Request_Method__c = request.requestMethod,
                RES_Request_Name__c = request.requestName,
                RES_Retry_Count__c = 0,
                RES_Type_of_Failure__c = failureType,
                RES_Headers__c = request.headers != null
                    ? JSON.serialize(request.headers)
                    : null,
                RES_Callout_Service__c = request.calloutService,
                RES_Record_Id__c = request.recordId
            );

            try{
                Database.insert(
                    log,
                    true,
                    AccessLevel.SYSTEM_MODE
                );

            }catch(Exception e){
                System.debug(
                    'Fail to create failure logs ' + e.getMessage()
                );
            }

        }catch(Exception e){
            System.debug(
                'Exception creating Integration logs ' + e.getMessage()
            );
        }
    }
}