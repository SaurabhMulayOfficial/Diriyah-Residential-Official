/**
 * @description
 * Integration service responsible for synchronizing Salesforce Contract
 * update events with the external SAP system via the CONTRACT_UPDATE endpoint.
 *
 * This class extends RES_BaseIntegrationCalloutService to leverage the
 * common integration framework for HTTP callout configuration, request
 * execution, retry handling, timeout management, and response processing.
 *
 * @author Saurabh Mulay
 */
public with sharing class RES_ContractUpdateIntegrationService extends RES_BaseIntegrationCalloutService {

    public RES_ContractUpdateIntegrationService(String requestMethod) {
        super();

        List<RES_API_Configuration__mdt> apiConfigList = new RES_APIConfigurationsDAO().getAPIConfiguration(requestMethod, 'Sales_Contract_Update');

        if (apiConfigList.isEmpty()) {
            throw new RES_IntegrationException('No API configuration found for Sales Contract Update integration with request method: ' + requestMethod);
        }

        setEndpoint(apiConfigList[0].RES_Endpoint__c);

        Integer maxRetries = apiConfigList[0].RES_Max_Retries__c != null ? Integer.valueOf(apiConfigList[0].RES_Max_Retries__c) : 3;
        Integer timeout   = apiConfigList[0].RES_Callout_Timeout__c != null ? Integer.valueOf(apiConfigList[0].RES_Callout_Timeout__c) : 10000;

        String sapToken = new RES_SAPTokenProvider().getToken();
        if (sapToken == null || String.isBlank(sapToken)) {
            throw new RES_IntegrationException('Failed to retrieve SAP token for Contract Update integration.');
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
        setRequestName('Sales_Contract_Update');
    }

    private static RES_ContractUpdateWrapper buildUpdateWrapper(Contract c) {
        RES_ContractUpdateWrapper wrapper = new RES_ContractUpdateWrapper();
        RES_ContractUpdateWrapper.ContractUpdatePayload payload = new RES_ContractUpdateWrapper.ContractUpdatePayload();

        payload.IV_COMPANY_CODE    = c.RES_Company_Code__c;
        payload.IV_CONTRACT        = null;
        payload.IV_CONTRACT_STATUS = c.RES_Approval_Status__c;
        payload.IV_WF_TYPE         = 'SCAC';
        payload.IV_C4C_USER        = null;
        payload.IV_NOTICE_DATE     = c.TerminationDateTime != null ? String.valueOf(c.TerminationDateTime) : null;
        payload.IV_CN_OFFR         = null;
        payload.IV_RETAIL          = null;
        payload.IV_RESERVDATE      = null;
        payload.IV_CT_FLAG         = false;
        payload.TEST_RUN           = false;

        wrapper.CONTRACT_UPDATE = payload;
        return wrapper;
    }

    private static String serializeWrapper(List<RES_ContractUpdateWrapper> wrappers) {
        if (wrappers.size() == 1) {
            return JSON.serialize(wrappers[0], true);
        }
        return JSON.serialize(wrappers, true);
    }

    public static String hydrateRequestBody(List<Contract> contracts) {
        if (contracts == null || contracts.isEmpty()) {
            throw new RES_IntegrationException('No Contract records provided for Contract Update integration.');
        }

        List<RES_ContractUpdateWrapper> wrapperList = new List<RES_ContractUpdateWrapper>();

        for (Contract c : contracts) {
            wrapperList.add(buildUpdateWrapper(c));
        }

        if (wrapperList.isEmpty()) {
            throw new RES_IntegrationException('Empty Wrapper List: Contract Update Sync');
        }

        return serializeWrapper(wrapperList);
    }

    private static Boolean processResponse(
        String responseBody,
        RES_ContractUpdateIntegrationService service,
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
                'Sales_Contract_Update',
                '',
                errorMessage,
                JSON.serialize(service.getHeaders()),
                objectType,
                recordId,
                String.valueOf(service.getRequestBody()),
                service.getRequestMethod(),
                'Sales_Contract_Update',
                service.getRetryCount(),
                'Client Side'
            );
            RES_ResponseWrapper.logError(log);
        }

        return isSuccess;
    }

    public static void syncContracts(List<Contract> contracts, String requestMethod) {
        RES_ContractUpdateIntegrationService service = new RES_ContractUpdateIntegrationService(requestMethod);
        String body = hydrateRequestBody(contracts);

        service.setBody(body);
        service.setRecordId(String.valueOf(contracts[0].Id));

        try {
            RES_IntegrationResponse response = service.sendRequest();

            System.debug(
                'Contract Update Integration Service | ' +
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
            System.debug('Exception occurred while calling the Contract Update Integration Service: ' + e.getMessage());
        }
    }
}
