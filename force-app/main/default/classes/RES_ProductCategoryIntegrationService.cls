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
        setTimeout(timeout);
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
            return JSON.serialize(requestWrappers[0], true);
        }
        return JSON.serialize(requestWrappers, true);
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
            return JSON.serialize(requestWrappers[0], true);
        }

        return JSON.serialize(requestWrappers, true);
    }

    private static Boolean processResponse(
        String responseBody,
        RES_ProductCategoryIntegrationService service,
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
                'ProductCategory_Sync',
                '',
                errorMessage,
                JSON.serialize(service.getHeaders()),
                objectType,
                recordId,
                String.valueOf(service.getRequestBody()),
                service.getRequestMethod(),
                'ProductCategory_Sync',
                service.getRetryCount(),
                'Client Side'
            );
            RES_ResponseWrapper.logError(log);
        }

        return isSuccess;
    }

    public static void syncMeasurements(List<RES_Measurement__c> measurements, String requestMethod, String triggerContext){
        RES_ProductCategoryIntegrationService service = new RES_ProductCategoryIntegrationService(requestMethod);
        String body = service.hydrateRequestBodyForMeasurements(measurements, triggerContext);
        service.setObjectName('Measurement');
        service.setRequestName('Measurement_Sync_Category');
        service.setBody(body);
        service.setRecordId(String.valueOf(measurements[0].Id));

        try{
            RES_IntegrationResponse response = service.sendRequest();

            System.debug(
                'Measurement Integration Service | ' +
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

        }catch(Exception e){
            System.debug('Exception Occur while calling the Measurement Integration Service: ' + e.getMessage());
        }
    }


    public static void syncProductCategories(List<ProductCategory> productCategories, String requestMethod, String triggerContext){
        RES_ProductCategoryIntegrationService service = new RES_ProductCategoryIntegrationService(requestMethod);
        String body = service.hydrateRequestBody(productCategories, triggerContext);
        service.setObjectName('ProductCategory');
        service.setRequestName('ProductCategory_Sync');
        service.setRecordId(String.valueOf(productCategories[0].Id));
        service.setBody(body);

        try{
            RES_IntegrationResponse response = service.sendRequest();

            System.debug(
                'Product Category Integration Service | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );

            Boolean isSuccess = processResponse(
                response.responseBody,
                service,
                productCategories[0].Id,
                'ProductCategory'
            );

            if (isSuccess) {
                ProductCategory toUpdate = new ProductCategory(
                    Id = productCategories[0].Id,
                    RES_Last_Sync_DateTime__c = System.now()
                );
                Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            }

        }catch(Exception e){
            System.debug('Exception Occur while calling the Product Category Integration Service: ' + e.getMessage());
        }
    }
}