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
        List<RES_API_Configuration__mdt> apiConfigList = new RES_APIConfigurationsDAO().getAPIConfiguration(requestMethod, 'Building_Land_API');

        if(apiConfigList.isEmpty()){
            throw new RES_IntegrationException('No API configuration found for ProductCategory integration with request method: ' + requestMethod);
        }

        setEndpoint(
            apiConfigList[0].RES_Endpoint__c
        );

        Integer maxRetries = apiConfigList[0].RES_Max_Retries__c != null ? Integer.valueOf(apiConfigList[0].RES_Max_Retries__c) : 3;
        Integer timeout = apiConfigList[0].RES_Callout_Timeout__c != null ? Integer.valueOf(apiConfigList[0].RES_Callout_Timeout__c) : 10000;

        String sapToken = new RES_SAPTokenProvider().getToken();
        if(sapToken == null || String.isBlank(sapToken)){
            throw new RES_IntegrationException('Failed to retrieve SAP token for ProductCategory integration.');
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
        setObjectName('ProductCategory');
        setTimeout(timeout);
        setRequestName('ProductCategory_Sync');
    }

    public String hydrateRequestBody(List<ProductCategory> productCategories, String triggerContext){
        if(productCategories == null || productCategories.isEmpty()){
            throw new RES_IntegrationException('No ProductCategory records provided for integration.');
        }

        List<RES_ProductCategoryRequestWrapper> requestWrappers  = new List<RES_ProductCategoryRequestWrapper>();
        for(ProductCategory pc: productCategories){
            RES_ProductCategoryRequestWrapper wrapper = new RES_ProductCategoryRequestWrapper();
            wrapper.RES_Company_Code = pc.RES_Company_Code__c;
            wrapper.RES_Business_Entity_Id = pc.RES_Business_Entity_Id__c;
            wrapper.RES_Property_ID = pc.RES_Property_ID__c;
            wrapper.Name = pc.Name;
            wrapper.RES_Valid_From_Date = pc.RES_Valid_From_Date__c;
            wrapper.RES_Valid_To_Date = pc.RES_Valid_To_Date__c;
            wrapper.RES_Profit_Center = pc.RES_Profit_Center__c;
            wrapper.RES_Property_Type = pc.RES_Property_Type__c;
            wrapper.Change_Indicator = triggerContext;
            requestWrappers.add(wrapper);
        }  

        if(requestWrappers.isEmpty()){
            throw new RES_IntegrationException('No valid ProductCategory records found for integration.');
        }

        if(requestWrappers.size() == 1){
            return JSON.serialize(requestWrappers[0]);
        }
        return JSON.serialize(requestWrappers);
    }


    public String hydrateRequestBodyForMeasurements(List<RES_Measurement__c> measurements, String triggerContext){
        if(measurements == null || measurements.isEmpty()){
            throw new RES_IntegrationException('No Measurement records provided for integration.');
        }
        
        Set<Id> categoryIds = new Set<Id>();
        for(RES_Measurement__c measurement: measurements){
            if(measurement.RES_Category__c != null){
                categoryIds.add(measurement.RES_Category__c);
            }
        }

        List<ProductCategory> categories = new RES_ProductCategoryDAOLayer().getCategoriesByIds(categoryIds);
        Map<Id, ProductCategory> categoryMap = new Map<Id, ProductCategory>();
        for(ProductCategory category: categories){
            categoryMap.put(category.Id, category);
        }
        
        List<RES_ProductCategoryRequestWrapper> requestWrappers  = new List<RES_ProductCategoryRequestWrapper>();
        Map<Id, List<RES_Measurement__c>> measurementMap = new Map<Id, List<RES_Measurement__c>>();
        
        for(RES_Measurement__c measurement: measurements){
            if(measurement.RES_Category__c != null){
                if(!measurementMap.containsKey(measurement.RES_Category__c)){
                    measurementMap.put(measurement.RES_Category__c, new List<RES_Measurement__c>());
                }
                measurementMap.get(measurement.RES_Category__c).add(measurement);
            }
        }

        for(Id categoryId: measurementMap.keySet()){
            ProductCategory category = categoryMap.get(categoryId);
            if(category != null){
                RES_ProductCategoryRequestWrapper wrapper = new RES_ProductCategoryRequestWrapper();
                wrapper.RES_Company_Code = category.RES_Company_Code__c;
                wrapper.RES_Business_Entity_Id = category.RES_Business_Entity_Id__c;
                wrapper.RES_Property_ID = category.RES_Property_ID__c;
                wrapper.Name = category.Name;
                wrapper.RES_Valid_From_Date = category.RES_Valid_From_Date__c;
                wrapper.RES_Valid_To_Date = category.RES_Valid_To_Date__c;
                wrapper.RES_Profit_Center = category.RES_Profit_Center__c;
                wrapper.RES_Property_Type = category.RES_Property_Type__c;
                wrapper.Change_Indicator = 'U';

                List<RES_ProductCategoryRequestWrapper.Measurement> measurementWrappers = new List<RES_ProductCategoryRequestWrapper.Measurement>();
                for(RES_Measurement__c measurement: measurementMap.get(categoryId)){
                    RES_ProductCategoryRequestWrapper.Measurement measurementWrapper = new RES_ProductCategoryRequestWrapper.Measurement();
                    measurementWrapper.RES_Measurement_Type = measurement.RES_Measurement_Type__c;
                    measurementWrapper.RES_Measurement_Amount = measurement.RES_Measurement_Amount__c;
                    measurementWrapper.RES_Measurement_From = measurement.RES_Measurement_From__c;
                    measurementWrapper.RES_Measurement_To = measurement.RES_Measurement_To__c;
                    measurementWrapper.Measurement_Change_Indicator = triggerContext;
                    measurementWrappers.add(measurementWrapper);
                }
                wrapper.RES_Measurements = measurementWrappers;
                requestWrappers.add(wrapper);
            }
        }

        if(requestWrappers.isEmpty()){
            throw new RES_IntegrationException('Empty Request Body while Hydrating measurement Request');
        }

        if(requestWrappers.size() == 1){
            return JSON.serialize(requestWrappers[0]);
        }

        return JSON.serialize(requestWrappers);
    }

    public static void syncMeasurements(List<RES_Measurement__c> measurements, String requestMethod, String triggerContext){
        RES_ProductCategoryIntegrationService service = new RES_ProductCategoryIntegrationService(requestMethod);
        String body = service.hydrateRequestBodyForMeasurements(measurements, triggerContext);

        service.setBody(body);
        
        try{
            RES_IntegrationResponse response = service.sendRequest();
            System.debug(
                'Measurement Integration Service | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );

            List<RES_Measurement__c> toUpdate = new List<RES_Measurement__c>();
            for(RES_Measurement__c m : measurements){
                RES_Measurement__c copy = new RES_Measurement__c(Id = m.Id);
                copy.RES_Last_Sync_DateTime__c = SYSTEM.now();
                toUpdate.add(copy);
            }

            if(!toUpdate.isEmpty()){
                Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            }
            
        }catch(Exception e){
            System.debug('Exception Occur while calling the Measurement Integration Service: ' + e.getMessage());
        }
    }


    public static void syncProductCategories(List<ProductCategory> productCategories, String requestMethod, String triggerContext){
        RES_ProductCategoryIntegrationService service = new RES_ProductCategoryIntegrationService(requestMethod);
        String body = service.hydrateRequestBody(productCategories, triggerContext);

        service.setBody(body);
        
        try{
            RES_IntegrationResponse response = service.sendRequest();
            System.debug(
                'Product Category Integration Service | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );

            List<productCategory> toUpdate = new List<productCategory>();
            for(ProductCategory pc : productCategories){
                ProductCategory copy = new ProductCategory(Id = pc.Id);
                copy.RES_Last_Sync_DateTime__c = SYSTEM.now();
                toUpdate.add(copy);
            }

            if(!toUpdate.isEmpty()){
                Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            }
            
        }catch(Exception e){
            System.debug('Exception Occur while calling the Product Category Integration Service: ' + e.getMessage());
        }
    }
}