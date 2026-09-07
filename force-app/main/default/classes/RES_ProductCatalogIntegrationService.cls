/**
 * @description
 * Integration service responsible for synchronizing Salesforce ProductCatalog
 * records with the external Product management system.
 *
 * This class extends RES_BaseIntegrationCalloutService to leverage the
 * common integration framework for HTTP callout configuration, request
 * execution, retry handling, timeout management, and response processing.
 *
 * The request payload is generated using a typed ProductCatalog integration
 * wrapper and serialized into JSON before being sent to the external system.
 * 
 * @author Saurabh Mulay
 */

public with sharing class RES_ProductCatalogIntegrationService extends RES_BaseIntegrationCalloutService {
    public RES_ProductCatalogIntegrationService(String requestMethod) {
        super();

        setEndpoint(
            ''
        );
        setHeaders(new Map<String, String>{
            'Content-Type' => 'application/json'
        });

        setMaxRetries(3);
        setRequestMethod(requestMethod);
        setObjectName('ProductCatalog');
        setTimeout(10000);
        setRequestName('ProductCatalog_Sync');
    }

    public String hydrateRequestBody(List<ProductCatalog> productCatalogs){
        //refer a Wrapper class & build body around it.
        return '';
    }

    public static void syncProductCatalogs(List<ProductCatalog> productCatalogs, String requestMethod){
        RES_ProductCatalogIntegrationService service = new RES_ProductCatalogIntegrationService(requestMethod);
        String body = service.hydrateRequestBody(productCatalogs);

        service.setBody(body);
        
        try{
            RES_IntegrationResponse response = service.sendRequest();
            System.debug(
                'Product Catalog Integration Service | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );
        }catch(Exception e){
            System.debug('Exception Occur while calling the Product Catalog Integration Service: ' + e.getMessage());
        }
    }
}