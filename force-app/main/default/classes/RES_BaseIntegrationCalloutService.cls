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

        for(integer i = 0; i < maxRetries; i++){
            System.debug('Attempting request: ' + i);

            try{
                HttpResponse response = new Http().send(httpRequest);
                if(response != null){
                    Integer statusCode = response.getStatusCode();
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