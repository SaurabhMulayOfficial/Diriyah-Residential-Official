public class RES_IntegrationResponse {
    public Integer statusCode;
    public String responseBody;
    public String status;
    public Blob responseBodyBlog;
    public DOM.Document responseXML;

    public RES_IntegrationResponse(Integer statusCode, String responseBody, String status) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
        this.status = status;
    }

    public RES_IntegrationResponse(){}
    
}