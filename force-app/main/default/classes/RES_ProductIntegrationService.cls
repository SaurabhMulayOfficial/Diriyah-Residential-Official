/**
 * @description
 * Integration service responsible for synchronizing Salesforce Product2
 * records with the external Product management system.
 *
 * This class extends RES_BaseIntegrationCalloutService to leverage the
 * common integration framework for HTTP callout configuration, request
 * execution, retry handling, timeout management, and response processing.
 *
 * The request payload is generated using a typed Product2 integration
 * wrapper and serialized into JSON before being sent to the external system.
 * 
 * @author Saurabh Mulay
 */

public with sharing class RES_ProductIntegrationService extends RES_BaseIntegrationCalloutService {
    public RES_ProductIntegrationService(String requestMethod) {
        super();

        setEndpoint(
            ''
        );
        setHeaders(new Map<String, String>{
            'Content-Type' => 'application/json'
        });

        setMaxRetries(3);
        setRequestMethod(requestMethod);
        setObjectName('Product2');
        setTimeout(10000);
        setRequestName('Product_Sync');
    }

    public String hydrateRequestBody(List<Product2> products){
        //refer a Wrapper class & build body around it.
        return '';
    }

    public static void syncProducts(List<Product2> products, String requestMethod){
        RES_ProductIntegrationService service = new RES_ProductIntegrationService(requestMethod);
        String body = service.hydrateRequestBody(products);

        service.setBody(body);
        
        try{
            RES_IntegrationResponse response = service.sendRequest();
            System.debug(
                'Product Integration Service | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );
        }catch(Exception e){
            System.debug('Exception Occur while calling the Product Integration Service: ' + e.getMessage());
        }
    }
}