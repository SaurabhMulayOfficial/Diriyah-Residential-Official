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

public without sharing class RES_ProductCatalogIntegrationService extends RES_BaseIntegrationCalloutService {
    public RES_ProductCatalogIntegrationService(String requestMethod) {
        super();
        List<RES_API_Configuration__mdt> apiConfigList = new RES_APIConfigurationsDAO().getAPIConfiguration(requestMethod, 'Product_Catalog_API');

        if(apiConfigList.isEmpty()){
            throw new RES_IntegrationException('No API configuration found for Product Catalog integration with request method: ' + requestMethod);
        }

        setEndpoint(
            apiConfigList[0].RES_Endpoint__c
        );

        Integer maxRetries = apiConfigList[0].RES_Max_Retries__c != null ? Integer.valueOf(apiConfigList[0].RES_Max_Retries__c) : 3;
        Integer timeout = apiConfigList[0].RES_Callout_Timeout__c != null ? Integer.valueOf(apiConfigList[0].RES_Callout_Timeout__c) : 10000;

        String sapToken = new RES_SAPTokenProvider().getToken();
        if(sapToken == null || String.isBlank(sapToken)){
            throw new RES_IntegrationException('Failed to retrieve SAP token for ProductCatalog integration.');
        }

        Map<String, String> headers = new Map<String, String>();

        if(apiConfigList[0].RES_Headers__c != null){
            Map<String, Object> inputHeaders = (Map<String, Object>) JSON.deserializeUntyped(apiConfigList[0].RES_Headers__c);
            for(String key: inputHeaders.keySet()){
                headers.put(key, String.valueOf(inputHeaders.get(key)));
            }
        }

        headers.put('Authorization', 'Bearer ' + sapToken);

        setHeaders(headers);
        setMaxRetries(maxRetries);
        setRequestMethod(requestMethod);
        setObjectName('ProductCatalog');
        setTimeout(timeout);
        setRequestName('ProductCatalog_Sync');

    }

    public static String hydrateProductCatalogBody(List<ProductCatalog> catalogs, String triggeringContext){
        if(catalogs == null || catalogs.isEmpty()){
            throw new RES_IntegrationException('No Product Catalog records provided for integration.');
        }

        List<RES_ProductCatalogWrapper> catalogWrapper = new List<RES_ProductCatalogWrapper>();

        for(ProductCatalog pc: catalogs){
            RES_ProductCatalogWrapper w = new RES_ProductCatalogWrapper();
            w.Change_Indicator = triggeringContext;
            w.EffectiveEndDate = String.valueOf(pc.EffectiveEndDate);
            w.EffectiveStartDate = String.valueOf(pc.EffectiveStartDate);
            w.Name = pc.Name;
            w.RES_BP_Number = pc.RES_BP_Number__c;
            w.RES_BP_Role = pc.RES_BP_Role__c;
            w.RES_Business_Entity_Id = pc.RES_Business_Entity_Id__c;
            w.RES_Company_Code = pc.RES_Company_Code__c;
            w.RES_Profit_Center = pc.RES_Profit_Center__c;
            w.RES_Tenancy_Law = pc.RES_Tenancy_Law__c;

            List<RES_ProductCatalogWrapper.CustomFieldWrapper> customFields = new List<RES_ProductCatalogWrapper.CustomFieldWrapper>();
            
            if(pc.RES_Name_AR__c != null) {
                customFields.add(
                    new RES_ProductCatalogWrapper.CustomFieldWrapper(
                        'RES_Name_AR',
                        pc.RES_Name_AR__c
                    )
                );
            }
            if(pc.RES_Geo_Latitude__c != null) {
                customFields.add(
                    new RES_ProductCatalogWrapper.CustomFieldWrapper(
                        'RES_Geo_Latitude',
                        String.valueOf(pc.RES_Geo_Latitude__c)
                    )
                );
            }
            if(pc.RES_Geo_Longitude__c != null) {
                customFields.add(
                    new RES_ProductCatalogWrapper.CustomFieldWrapper(
                        'RES_Geo_Longitude',
                        String.valueOf(pc.RES_Geo_Longitude__c)
                    )
                );
            }
            if(pc.RES_Master_Plan__c != null) {
                customFields.add(
                    new RES_ProductCatalogWrapper.CustomFieldWrapper(
                        'RES_Master_Plan',
                        pc.RES_Master_Plan__c
                    )
                );
            }

            w.RES_CustomFields = customFields;
            catalogWrapper.add(w);
        }

        if(catalogWrapper.isEmpty()){
            throw new RES_IntegrationException('Empty Catalog Wrapper');
        }

        if(catalogWrapper.size() == 1){
            return JSON.serialize(catalogWrapper[0], true);
        }

        return JSON.serialize(catalogWrapper, true);
    }

    public static String hydrateCatalogWithMeasurements(List<RES_Measurement__c> measurements, String triggeringContext){
        Set<Id> catalogIds = new Set<Id>();
        for(RES_Measurement__c m :measurements){
            if(m.RES_Catalog__c != null){
                catalogIds.add(m.RES_Catalog__c);
            }
        }

        if(catalogIds.isEmpty())throw new RES_IntegrationException('No Product Catalog Associated With Measurement.');

        List<ProductCatalog> catalogs = new RES_ProductCatalogDAOLayer().getCatalogByIds(catalogIds);
        Map<Id, List<RES_Measurement__c>> catalogToMeasurementMapping = new Map<Id, List<RES_Measurement__c>>();

        for(RES_Measurement__c m: measurements){
            if(m.RES_Catalog__c != null){
                if(!catalogToMeasurementMapping.containsKey(m.RES_Catalog__c)){
                    catalogToMeasurementMapping.put(m.RES_Catalog__c, new List<RES_Measurement__c>());
                }
                
                catalogToMeasurementMapping.get(m.RES_Catalog__c).add(m);
            }
        }

        List<RES_ProductCatalogWrapper> catalogWrapper = new List<RES_ProductCatalogWrapper>();

        for(ProductCatalog pc: catalogs){
            if(catalogToMeasurementMapping.containsKey(pc.Id) && !catalogToMeasurementMapping.get(pc.Id).isEmpty()){
                RES_ProductCatalogWrapper w = new RES_ProductCatalogWrapper();
                w.Change_Indicator = 'U';
                w.EffectiveEndDate = String.valueOf(pc.EffectiveEndDate);
                w.EffectiveStartDate = String.valueOf(pc.EffectiveStartDate);
                w.Name = pc.Name;
                w.RES_BP_Number = pc.RES_BP_Number__c;
                w.RES_BP_Role = pc.RES_BP_Role__c;
                w.RES_Business_Entity_Id = pc.RES_Business_Entity_Id__c;
                w.RES_Company_Code = pc.RES_Company_Code__c;
                w.RES_Profit_Center = pc.RES_Profit_Center__c;
                w.RES_Tenancy_Law = pc.RES_Tenancy_Law__c;

                List<RES_ProductCatalogWrapper.MeasurementWrapper> measurementsWrapper = new List<RES_ProductCatalogWrapper.MeasurementWrapper>();

                for(RES_Measurement__c m : catalogToMeasurementMapping.get(pc.Id)){
                    RES_ProductCatalogWrapper.MeasurementWrapper mW = new RES_ProductCatalogWrapper.MeasurementWrapper();
                    mW.Measurement_Change_Indicator = triggeringContext;
                    mW.RES_Measurement_Amount = m.RES_Measurement_Amount__c;
                    mW.RES_Measurement_From = String.valueOf(m.RES_Measurement_From__c);
                    mW.RES_Measurement_To = String.valueOf(m.RES_Measurement_To__c);
                    mW.RES_Measurement_Type = m.RES_Measurement_Type__c;
                    measurementsWrapper.add(mW);
                }
                
                if(measurementsWrapper.size() > 0){
                    w.RES_Measurements = measurementsWrapper;
                }

                catalogWrapper.add(w);
            }    
        }

        if(catalogWrapper.size() <= 0){
            throw new RES_IntegrationException('Empty Request Body: (Measurements w.r.t. Catalog)');
        }

        if(catalogWrapper.size() == 1){
            return JSON.serialize(catalogWrapper[0], true);
        }

        return JSON.serialize(catalogWrapper, true);
    }

    private static Boolean processResponse(
        String responseBody,
        RES_ProductCatalogIntegrationService service,
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
                'ProductCatalog_Sync',
                '',
                errorMessage,
                JSON.serialize(service.getHeaders()),
                objectType,
                recordId,
                String.valueOf(service.getRequestBody()),
                service.getRequestMethod(),
                'ProductCatalog_Sync',
                service.getRetryCount(),
                'Client Side'
            );
            RES_ResponseWrapper.logError(log);
        }

        return isSuccess;
    }

    public static void syncProductCatalogs(List<ProductCatalog> catalogs, String requestMethod, String triggeringContext){
        RES_ProductCatalogIntegrationService service = new RES_ProductCatalogIntegrationService(requestMethod);
        String body = hydrateProductCatalogBody(catalogs, triggeringContext);

        service.setBody(body);

        try {
            RES_IntegrationResponse response = service.sendRequest();

            System.debug(
                'Product Catalog Integration Service | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );

            Boolean isSuccess = processResponse(
                response.responseBody,
                service,
                catalogs[0].Id,
                'ProductCatalog'
            );

            if (isSuccess) {
                ProductCatalog toUpdate = new ProductCatalog(
                    Id = catalogs[0].Id,
                    RES_Last_Sync_DateTime__c = System.now()
                );
                Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            }

        } catch (Exception e) {
            System.debug('Exception occurred while calling the Product Catalog Integration Service: ' + e.getMessage());
        }
    }

    public static void syncMeasurementsWithProductCatalog(List<RES_Measurement__c> measurements, String requestMethod, String triggeringContext){
        RES_ProductCatalogIntegrationService service = new RES_ProductCatalogIntegrationService(requestMethod);
        String body = hydrateCatalogWithMeasurements(measurements, triggeringContext);

        service.setBody(body);

        try {
            RES_IntegrationResponse response = service.sendRequest();

            System.debug(
                'Product Catalog (Measurement) Integration Service | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );

            Boolean isSuccess = processResponse(
                response.responseBody,
                service,
                measurements[0].Id,
                'RES_Measurement__c'
            );

            if (isSuccess) {
                RES_Measurement__c toUpdate = new RES_Measurement__c(
                    Id = measurements[0].Id,
                    RES_Last_Sync_DateTime__c = System.now()
                );
                Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            }

        } catch (Exception e) {
            System.debug('Exception occurred while calling the Product Catalog Measurement Integration Service: ' + e.getMessage());
        }
    }
}