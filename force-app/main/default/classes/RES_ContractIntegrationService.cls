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

        setEndpoint(
            ''
        );
        setHeaders(new Map<String, String>{
            'Content-Type' => 'application/json'
        });

        setMaxRetries(3);
        setRequestMethod(requestMethod);
        setObjectName('Contract');
        setTimeout(10000);
        setRequestName('Contract_Sync');
    }

    public String hydrateRequestBody(List<Contract> contracts){
        //refer a Wrapper class & build body around it.
        return '';
    }

    public static void syncContracts(List<Contract> contracts, String requestMethod){
        RES_ContractIntegrationService service = new RES_ContractIntegrationService(requestMethod);
        String body = service.hydrateRequestBody(contracts);

        service.setBody(body);
        
        try{
            RES_IntegrationResponse response = service.sendRequest();
            System.debug(
                'Contract Integration Response | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );
        }catch(Exception e){
            System.debug('Exception Occur while calling the Contract Integration Service: ' + e.getMessage());
        }
    }
}