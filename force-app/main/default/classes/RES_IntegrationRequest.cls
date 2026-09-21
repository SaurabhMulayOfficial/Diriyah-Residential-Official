public class RES_IntegrationRequest {
    public String endpoint;
    public Map<String, String> headers;
    public String requestName;
    public String requestMethod;
    public String requestBody;
    public Integer maxRetries;
    public Integer timeout;
    public String objectName;
    public String calloutService;
    
    public RES_IntegrationRequest(){

    }
    
    public RES_IntegrationRequest(String endpoint, Map<String, String> headers, String requestName, String requestMethod, String requestBody, Integer maxRetries, Integer timeout, String objectName, String calloutService) {
        this.endpoint = endpoint;
        this.headers = headers;
        this.requestMethod = requestMethod;
        this.requestBody = requestBody;
        this.timeout = timeout;
        this.maxRetries = maxRetries;
        this.requestName = requestName;
        this.objectName = objectName;
        this.calloutService = calloutService;
    }
}