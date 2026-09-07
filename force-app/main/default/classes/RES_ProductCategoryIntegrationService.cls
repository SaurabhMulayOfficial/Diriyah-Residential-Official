/**
 * @description
 * Integration service responsible for synchronizing Salesforce ProductCategory
 * records with the external Product management system.
 *
 * This class extends RES_BaseIntegrationCalloutService to leverage the
 * common integration framework for HTTP callout configuration, request
 * execution, retry handling, timeout management, and response processing.
 *
 * The request payload is generated using a typed ProductCategory integration
 * wrapper and serialized into JSON before being sent to the external system.
 * 
 * @author Saurabh Mulay
 */

public with sharing class RES_ProductCategoryIntegrationService extends RES_BaseIntegrationCalloutService {
    public RES_ProductCategoryIntegrationService(String requestMethod) {
        super();

        setEndpoint(
            ''
        );
        setHeaders(new Map<String, String>{
            'Content-Type' => 'application/json'
        });

        setMaxRetries(3);
        setRequestMethod(requestMethod);
        setObjectName('ProductCategory');
        setTimeout(10000);
        setRequestName('ProductCategory_Sync');
    }

    public String hydrateRequestBody(List<ProductCategory> productCategories){
        //refer a Wrapper class & build body around it.
        return '';
    }

    public static void syncProductCategories(List<ProductCategory> productCategories, String requestMethod){
        RES_ProductCategoryIntegrationService service = new RES_ProductCategoryIntegrationService(requestMethod);
        String body = service.hydrateRequestBody(productCategories);

        service.setBody(body);
        
        try{
            RES_IntegrationResponse response = service.sendRequest();
            System.debug(
                'Product Category Integration Service | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );
        }catch(Exception e){
            System.debug('Exception Occur while calling the Product Category Integration Service: ' + e.getMessage());
        }
    }
}