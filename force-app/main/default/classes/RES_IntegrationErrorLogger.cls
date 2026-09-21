/**
 * @description Wrapper for RES_Integration_Log__c.
 *              Encapsulates integration request, response, and failure details
 *              used for creating integration log records.
 */
public class RES_IntegrationErrorLogger {

    public String calloutService;
    public String classMethod;
    public String errorMessage;
    public String headers;
    public String objectName;
    public String recordId;
    public String requestBody;
    public String requestMethod;
    public String requestName;
    public Decimal retryCount;
    public String typeOfFailure;

    public RES_IntegrationErrorLogger() {}

    public RES_IntegrationErrorLogger(
        String calloutService,
        String classMethod,
        String errorMessage,
        String headers,
        String objectName,
        String recordId,
        String requestBody,
        String requestMethod,
        String requestName,
        Decimal retryCount,
        String typeOfFailure
    ) {
        this.calloutService = calloutService;
        this.classMethod = classMethod;
        this.errorMessage = errorMessage;
        this.headers = headers;
        this.objectName = objectName;
        this.recordId = recordId;
        this.requestBody = requestBody;
        this.requestMethod = requestMethod;
        this.requestName = requestName;
        this.retryCount = retryCount;
        this.typeOfFailure = typeOfFailure;
    }


    public static void log(RES_IntegrationErrorLogger logWrapper){
        RES_Integration_Log__c logRecord = new RES_Integration_Log__c(
            RES_Callout_Service__c = logWrapper.calloutService,
            RES_Class_Method__c = logWrapper.classMethod,
            RES_Error_Message__c = logWrapper.errorMessage,
            RES_Object_Name__c = logWrapper.objectName,
            RES_Record_Id__c = logWrapper.recordId,
            RES_Request_Name__c = logWrapper.requestName,
            RES_Request_Method__c = logWrapper.requestMethod,
            RES_Request_Body__c = logWrapper.requestBody,
            RES_Headers__c = logWrapper.headers,
            RES_Retry_Count__c = logWrapper.retryCount,
            RES_Type_of_Failure__c = logWrapper.typeOfFailure
        );

        Database.insert(logRecord);
    }
}