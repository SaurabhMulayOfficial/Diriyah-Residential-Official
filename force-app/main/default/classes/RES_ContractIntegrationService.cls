/**
 * @description
 * Integration service responsible for synchronizing Salesforce Contract
 * records with the external Contract management system.
 *
 * This class extends RES_BaseIntegrationCalloutService to leverage the
 * common integration framework for HTTP callout configuration, request
 * execution, retry handling, timeout management, and response processing.
 *
 * The request payload is generated through a typed Contract integration
 * wrapper and serialized into JSON before being sent to the external system.
 *
 * @author Saurabh Mulay
 */

public with sharing class RES_ContractIntegrationService extends RES_BaseIntegrationCalloutService {
    public RES_ContractIntegrationService(String requestMethod) {
        super();

        List<RES_API_Configuration__mdt> apiConfigList = new RES_APIConfigurationsDAO().getAPIConfiguration(requestMethod, 'Sales_Contract_Creation');

        if (apiConfigList.isEmpty()) {
            throw new RES_IntegrationException('No API configuration found for Sales Contract Creation integration with request method: ' + requestMethod);
        }

        setEndpoint(apiConfigList[0].RES_Endpoint__c);

        Integer maxRetries = apiConfigList[0].RES_Max_Retries__c != null ? Integer.valueOf(apiConfigList[0].RES_Max_Retries__c) : 3;
        Integer timeout = apiConfigList[0].RES_Callout_Timeout__c != null ? Integer.valueOf(apiConfigList[0].RES_Callout_Timeout__c) : 10000;

        String sapToken = new RES_SAPTokenProvider().getToken();
        if (sapToken == null || String.isBlank(sapToken)) {
            throw new RES_IntegrationException('Failed to retrieve SAP token for Contract Creation integration.');
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
        setRequestName('Sales_Contract_Creation');
    }

    public String hydrateRequestBody(List<Contract> contracts) {
        if(contracts.isEmpty()){
            throw new RES_IntegrationException('No Contract Record Provided to Create Request Body.');
        }

        Set<Id> contractIds = new Set<Id>();
        for(Contract c: contracts)contractIds.add(c.Id);

        List<ContractItemPrice> contractItemPriceList = new RES_ContractItemPriceDAOLayer().getCIPByContractIds(contractIds);
        Map<Id, Map<String, String>> mapping = new Map<Id, Map<String, String>>();
        Map<Id, ContractItemPrice> unitMapping = new Map<Id, ContractItemPrice>();

        for(ContractItemPrice cip: contractItemPriceList){
            if(cip.ContractId != null){
                if(!mapping.containsKey(cip.ContractId)){
                    mapping.put(cip.ContractId, new Map<String, String>());
                }
                
                if(cip.RES_CIP_Type__c == 'Payment Plan'){
                    mapping.get(cip.ContractId).put(cip.RES_CIP_Type__c, String.valueOf(cip.RES_Product__r.RES_Product_External_ID__c));
                }
                else if(cip.RES_CIP_Type__c == 'Unit'){
                    mapping.get(cip.ContractId).put(cip.RES_CIP_Type__c, String.valueOf(cip.Price));
                    unitMapping.put(cip.ContractId, cip);
                }   
            }
        }

        List<RES_ContractCreationWrapper.ContractCreationPayload> contractWrapperList = new List<RES_ContractCreationWrapper.ContractCreationPayload>();

        for(Contract c: contracts){
            RES_ContractCreationWrapper.ContractCreationPayload payload = new  RES_ContractCreationWrapper.ContractCreationPayload();
            List<RES_ContractCreationWrapper.PartnerWrapper> partner = new List<RES_ContractCreationWrapper.PartnerWrapper>();
            RES_ContractCreationWrapper.PartnerWrapper p1 = new  RES_ContractCreationWrapper.PartnerWrapper();
            p1.ROLE = c.Account.RES_BP_Role__c;
            p1.PARTNER = '20001621';

            partner.add(
                p1
            );
            
            if(!partner.isEmpty()){
                payload.IT_PARTNERS = partner;
            }

            payload.IV_C4CREF = c.Id;
            payload.IV_C4CUSR = c.Owner.Name;
            payload.IV_CN_STDATE = String.valueOf(c.StartDate);
            payload.IV_CN_ENDDATE = String.valueOf(c.EndDate);

            if(unitMapping.containsKey(c.Id)){
                ContractItemPrice unitCIP = unitMapping.get(c.Id);
                String objectID = String.valueOf(c.RES_Company_Code__c) + '/' + unitCIP.RES_Product__r.RES_API_Business_Entity__c;
                payload.IV_CONTRACT_OBJECT_ID = objectID;
            }
        
            if(mapping.containsKey(c.Id)){
                if(mapping.get(c.Id).containsKey('Payment Plan')){
                    payload.IV_PAYPLAN_ID = mapping.get(c.Id).get('Payment Plan');
                }
            }
            
            payload.IV_RECNTXT = c.ContractNumber;
            payload.IV_RECNTYPE = c.RES_Contract_Type__c;
            
            String firstTimeBuyer = (c.RES_First_Residential_Buyer__c == true? 'X': '');
            payload.IV_FIRST_TIME_BUYER = firstTimeBuyer;

            if(mapping.containsKey(c.Id)){
                if(mapping.get(c.Id).containsKey('Unit')){
                    payload.IV_UNIT_PRICE = mapping.get(c.Id).get('Unit');
                }
            }

            payload.IV_CONTRACT_CONCLUSION_DATE = String.valueOf(c.CompanySignedDate);
            payload.IV_RECNTXTOLD = c.DIR_Old_Contract__c;    

            contractWrapperList.add(payload);
        }

        if(contractWrapperList.isEmpty()){
            throw new RES_IntegrationException('Empty Wrapper List: Contract Creation Sync');
        }

        if(contractWrapperList.size() == 1){
            return JSON.serialize(contractWrapperList[0], true);
        }
    
        return JSON.serialize(contractWrapperList, true);
    }

    private static Boolean processResponse(
        String responseBody,
        RES_ContractIntegrationService service,
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
                'Sales_Contract_Creation',
                '',
                errorMessage,
                JSON.serialize(service.getHeaders()),
                objectType,
                recordId,
                String.valueOf(service.getRequestBody()),
                service.getRequestMethod(),
                'Sales_Contract_Creation',
                service.getRetryCount(),
                'Client Side'
            );
            RES_ResponseWrapper.logError(log);
        }

        return isSuccess;
    }

    public static void syncContracts(List<Contract> contracts, String requestMethod) {
        RES_ContractIntegrationService service = new RES_ContractIntegrationService(requestMethod);
        String body = service.hydrateRequestBody(contracts);

        service.setBody(body);
        service.setRecordId(String.valueOf(contracts[0].Id));

        try {
            RES_IntegrationResponse response = service.sendRequest();
            System.debug(
                'Contract Integration Response | ' +
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
            System.debug('Exception occurred while calling the Contract Integration Service: ' + e.getMessage());
        }
    }
}