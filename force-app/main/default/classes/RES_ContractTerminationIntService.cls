/**
 * @description
 * Integration service responsible for synchronizing Salesforce Contract
 * termination events with the external SAP system via the CONTRACT_TERM endpoint.
 *
 * This class extends RES_BaseIntegrationCalloutService to leverage the
 * common integration framework for HTTP callout configuration, request
 * execution, retry handling, timeout management, and response processing.
 *
 * @author Saurabh Mulay
 */
public with sharing class RES_ContractTerminationIntService extends RES_BaseIntegrationCalloutService {

    public RES_ContractTerminationIntService(String requestMethod) {
        super();

        List<RES_API_Configuration__mdt> apiConfigList = new RES_APIConfigurationsDAO().getAPIConfiguration(requestMethod, 'Sales_Contract_Termination');

        if (apiConfigList.isEmpty()) {
            throw new RES_IntegrationException('No API configuration found for Sales Contract Termination integration with request method: ' + requestMethod);
        }

        setEndpoint(apiConfigList[0].RES_Endpoint__c);

        Integer maxRetries = apiConfigList[0].RES_Max_Retries__c != null ? Integer.valueOf(apiConfigList[0].RES_Max_Retries__c) : 3;
        Integer timeout    = apiConfigList[0].RES_Callout_Timeout__c != null ? Integer.valueOf(apiConfigList[0].RES_Callout_Timeout__c) : 10000;

        String sapToken = new RES_SAPTokenProvider().getToken();
        if (sapToken == null || String.isBlank(sapToken)) {
            throw new RES_IntegrationException('Failed to retrieve SAP token for Contract Termination integration.');
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
        setObjectName('Contract');
        setTimeout(timeout);
        setRequestName('Sales_Contract_Termination');
    }

    private static RES_ContractTerminationWrapper buildTerminationWrapper(Contract c) {
        RES_ContractTerminationWrapper wrapper = new RES_ContractTerminationWrapper();
        RES_ContractTerminationWrapper.ContractTerminationPayload payload = new RES_ContractTerminationWrapper.ContractTerminationPayload();

        payload.IV_COMPANY_CODE           = c.RES_Company_Code__c;
        payload.IV_CONTRACT               = c.RES_S4_Contract_Id__c;
        payload.IV_ENTRY_DATE             = null;
        payload.IV_REQUESTED_DATE         = null;
        payload.IV_FINAL_TERMINATION_DATE = null;
        payload.IV_CONTRACT_STATUS        = c.RES_Approval_Status__c;
        payload.IV_TERMINATION_REASON     = c.RES_Cancellation_Reason__c;
        payload.IV_NOTE                   = null;
        payload.IV_C4CUSR                 = null;
        payload.IV_CONTRACT_OBJECT_ID     = null;
        payload.UNIT_STATUS               = null;

        wrapper.CONTRACT_TERM = payload;
        return wrapper;
    }

    private static String serializeWrapper(List<RES_ContractTerminationWrapper> wrappers) {
        if (wrappers.size() == 1) {
            return JSON.serialize(wrappers[0], true);
        }
        return JSON.serialize(wrappers, true);
    }

    public static String hydrateRequestBody(List<Contract> contracts) {
        if (contracts == null || contracts.isEmpty()) {
            throw new RES_IntegrationException('No Contract records provided for Contract Termination integration.');
        }

        List<RES_ContractTerminationWrapper> wrapperList = new List<RES_ContractTerminationWrapper>();

        for (Contract c : contracts) {
            wrapperList.add(buildTerminationWrapper(c));
        }

        if (wrapperList.isEmpty()) {
            throw new RES_IntegrationException('Empty Wrapper List: Contract Termination Sync');
        }

        return serializeWrapper(wrapperList);
    }

    private static Boolean processResponse(
        String responseBody,
        RES_ContractTerminationIntService service,
        Id recordId,
        String objectType
    ) {
        if (String.isBlank(responseBody)) {
            return false;
        }

        RES_ResponseWrapper responseWrapper = RES_ResponseWrapper.deserialize(responseBody);
        String errorMessage = '';
        Boolean isSuccess   = false;

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
                'Sales_Contract_Termination',
                '',
                errorMessage,
                JSON.serialize(service.getHeaders()),
                objectType,
                recordId,
                String.valueOf(service.getRequestBody()),
                service.getRequestMethod(),
                'Sales_Contract_Termination',
                service.getRetryCount(),
                'Client Side'
            );
            RES_ResponseWrapper.logError(log);
        }

        return isSuccess;
    }

    public static void syncContracts(List<Contract> contracts, String requestMethod) {
        RES_ContractTerminationIntService service = new RES_ContractTerminationIntService(requestMethod);
        String body = hydrateRequestBody(contracts);

        service.setBody(body);
        service.setRecordId(String.valueOf(contracts[0].Id));

        try {
            RES_IntegrationResponse response = service.sendRequest();

            System.debug(
                'Contract Termination Integration Service | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );

            Boolean isSuccess = processResponse(
                response.responseBody,
                service,
                contracts[0].Id,
                'Contract'
            );

            if (isSuccess) {
                Contract toUpdate = new Contract(
                    Id = contracts[0].Id,
                    RES_Last_Sync_DateTime__c = System.now()
                );
                Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            }

        } catch (Exception e) {
            System.debug('Exception occurred while calling the Contract Termination Integration Service: ' + e.getMessage());
        }
    }
}
