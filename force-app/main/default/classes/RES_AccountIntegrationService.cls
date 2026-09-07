/**
 * @description
 * Integration service responsible for synchronizing Salesforce Account
 * records with the external Account management system.
 *
 * This class extends RES_BaseIntegrationCalloutService to leverage the
 * common integration framework for HTTP callout configuration, request
 * execution, retry handling, timeout management, and response processing.
 *
 * The request payload is generated using a typed Account integration
 * wrapper and serialized into JSON before being sent to the external system.
 * 
 * @author Saurabh Mulay
 */

public with sharing class RES_AccountIntegrationService extends RES_BaseIntegrationCalloutService {
    public RES_AccountIntegrationService(String requestMethod) {
        super();

        setEndpoint(
            ''
        );
        setHeaders(new Map<String, String>{
            'Content-Type' => 'application/json'
        });

        setMaxRetries(3);
        setRequestMethod('POST');
        setObjectName('Account');
        setTimeout(10000);
        setRequestName('Account_Sync');
    }

    public String hydrateRequestBody(List<Account> accounts){
        //refer a Wrapper class & build body around it.
        return '';
    }

    public static void syncAccounts(List<Account> accounts, String requestMethod){
        RES_AccountIntegrationService service = new RES_AccountIntegrationService(requestMethod);
        String body = service.hydrateRequestBody(accounts);

        service.setBody(body);
        
        try{
            RES_IntegrationResponse response = service.sendRequest();
            System.debug(
                'Account Integration Service | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );
        }catch(Exception e){
            System.debug('Exception Occur while calling the Account Integration Service: ' + e.getMessage());
        }
    }
}