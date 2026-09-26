/**
 * @description
 * Integration service responsible for synchronizing Salesforce Payment Plan
 * records with the external SAP system.
 *
 * Extends RES_BaseIntegrationCalloutService for common HTTP callout handling,
 * retry logic, timeout management, and response processing.
 *
 * Supports both insert ('I') and update ('U') triggering contexts via a single
 * 'Payment_Plan' API configuration, differentiated by the triggering context
 * set on the integration request event.
 *
 * @author Saurabh Mulay
 */
public with sharing class RES_PaymentPlanIntegrationService extends RES_BaseIntegrationCalloutService {

    public RES_PaymentPlanIntegrationService(String requestMethod) {
        super();

        List<RES_API_Configuration__mdt> apiConfigList = new RES_APIConfigurationsDAO().getAPIConfiguration(requestMethod, 'Payment_Plan');

        if (apiConfigList.isEmpty()) {
            throw new RES_IntegrationException('No API configuration found for Payment Plan integration with request method: ' + requestMethod);
        }

        setEndpoint(apiConfigList[0].RES_Endpoint__c);

        Integer maxRetries = apiConfigList[0].RES_Max_Retries__c != null ? Integer.valueOf(apiConfigList[0].RES_Max_Retries__c) : 3;
        Integer timeout = apiConfigList[0].RES_Callout_Timeout__c != null ? Integer.valueOf(apiConfigList[0].RES_Callout_Timeout__c) : 10000;

        String sapToken = new RES_SAPTokenProvider().getToken();
        if (sapToken == null || String.isBlank(sapToken)) {
            throw new RES_IntegrationException('Failed to retrieve SAP token for Payment Plan integration.');
        }

        Map<String, String> headers = new Map<String, String>();

        if (apiConfigList[0].RES_Headers__c != null) {
            Map<String, Object> inputHeaders = (Map<String, Object>) JSON.deserializeUntyped(apiConfigList[0].RES_Headers__c);
            for (String key : inputHeaders.keySet()) {
                headers.put(key, String.valueOf(inputHeaders.get(key)));
            }
        }

        headers.put('Authorization', 'Bearer ' + sapToken);

        setHeaders(headers);
        setMaxRetries(maxRetries);
        setRequestMethod(requestMethod);
        setObjectName('RES_Payment_Plan__c');
        setTimeout(timeout);
        setRequestName('Payment_Plan');
    }

    public String hydrateRequestBody(List<RES_Payment_Plan__c> paymentPlans) {
        if (paymentPlans.isEmpty()) {
            throw new RES_IntegrationException('No Payment Plan Record Provided to Create Request Body.');
        }

        // TODO: Build Payment Plan + Installment payload using RES_PaymentPlanWrapper
        return '{}';
    }

    public String hydrateRequestBody(List<RES_Installment__c> installments) {
        if (installments.isEmpty()) {
            throw new RES_IntegrationException('No Installment Record Provided to Create Request Body.');
        }

        // TODO: Build Installment payload using RES_PaymentPlanWrapper
        return '{}';
    }

    private static Boolean processResponse(
        String responseBody,
        RES_PaymentPlanIntegrationService service,
        Id recordId,
        String objectType
    ) {
        if (String.isBlank(responseBody)) {
            return false;
        }

        RES_ResponseWrapper responseWrapper = RES_ResponseWrapper.deserialize(responseBody);
        String errorMessage = '';
        Boolean isSuccess = false;

        if (responseWrapper != null &&
            responseWrapper.responseReturn != null &&
            responseWrapper.responseReturn.item != null) {

            for (RES_ResponseWrapper.ItemWrapper item : responseWrapper.responseReturn.item) {
                if (item.type == 'E' && String.isNotBlank(item.message)) {
                    errorMessage += item.message;
                } else if (item.type == 'S') {
                    isSuccess = true;
                }
            }
        }

        if (String.isNotBlank(errorMessage)) {
            RES_IntegrationErrorLogger log = new RES_IntegrationErrorLogger(
                'Payment_Plan',
                '',
                errorMessage,
                JSON.serialize(service.getHeaders()),
                objectType,
                recordId,
                String.valueOf(service.getRequestBody()),
                service.getRequestMethod(),
                'Payment_Plan',
                service.getRetryCount(),
                'Client Side'
            );
            RES_ResponseWrapper.logError(log);
        }

        return isSuccess;
    }

    public static void syncPaymentPlans(List<RES_Payment_Plan__c> paymentPlans, String requestMethod, String triggerContext) {
        RES_PaymentPlanIntegrationService service = new RES_PaymentPlanIntegrationService(requestMethod);
        String body = service.hydrateRequestBody(paymentPlans);
        executeSync(service, body, paymentPlans[0].Id, 'RES_Payment_Plan__c');
    }

    public static void syncPaymentPlans(List<RES_Installment__c> installments, String requestMethod, String triggerContext) {
        RES_PaymentPlanIntegrationService service = new RES_PaymentPlanIntegrationService(requestMethod);
        String body = service.hydrateRequestBody(installments);
        executeSync(service, body, installments[0].Id, 'RES_Installment__c');
    }

    private static void executeSync(RES_PaymentPlanIntegrationService service, String body, Id recordId, String objectType) {
        service.setBody(body);
        service.setRecordId(String.valueOf(recordId));

        try {
            RES_IntegrationResponse response = service.sendRequest();
            System.debug(
                'Payment Plan Integration Response | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );

            Boolean isSuccess = processResponse(response.responseBody, service, recordId, objectType);

            if (isSuccess) {
                SObject toUpdate = Schema.getGlobalDescribe().get(objectType).newSObject(recordId);
                toUpdate.put('RES_Last_Sync_DateTime__c', System.now());
                Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            }

        } catch (Exception e) {
            System.debug('Exception occurred while calling the Payment Plan Integration Service: ' + e.getMessage());
        }
    }
}