/**
 * @description
 * Integration service responsible for synchronizing Salesforce Payment Plan
 * records with the external SAP system.
 *
 * Extends RES_BaseIntegrationCalloutService for common HTTP callout handling,
 * retry logic, timeout management, and response processing.
 *
 * Supports both insert ('I') and update ('U') triggering contexts via a single
 * 'Payment_Plan' API configuration, differentiated by the triggering context
 * set on the integration request event.
 *
 * @author Saurabh Mulay
 */
public with sharing class RES_PaymentPlanIntegrationService extends RES_BaseIntegrationCalloutService {

    public RES_PaymentPlanIntegrationService(String requestMethod) {
        super();

        List<RES_API_Configuration__mdt> apiConfigList = new RES_APIConfigurationsDAO().getAPIConfiguration(requestMethod, 'Payment_Plan');

        if (apiConfigList.isEmpty()) {
            throw new RES_IntegrationException('No API configuration found for Payment Plan integration with request method: ' + requestMethod);
        }

        setEndpoint(apiConfigList[0].RES_Endpoint__c);

        Integer maxRetries = apiConfigList[0].RES_Max_Retries__c != null ? Integer.valueOf(apiConfigList[0].RES_Max_Retries__c) : 3;
        Integer timeout = apiConfigList[0].RES_Callout_Timeout__c != null ? Integer.valueOf(apiConfigList[0].RES_Callout_Timeout__c) : 10000;

        String sapToken = new RES_SAPTokenProvider().getToken();
        if (sapToken == null || String.isBlank(sapToken)) {
            throw new RES_IntegrationException('Failed to retrieve SAP token for Payment Plan integration.');
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
        setObjectName('Product2');
        setTimeout(timeout);
        setRequestName('Payment_Plan');
    }

    public String hydrateRequestBody(List<Product2> paymentPlans, String triggerContext) {
        if (paymentPlans.isEmpty()) {
            throw new RES_IntegrationException('No Payment Plan Record Provided to Create Request Body.');
        }
		
        // TODO: Build Payment Plan + Installment payload using RES_PaymentPlanWrapper
        Set<Id> paymentPlanIds = new Set<Id>();
        RES_PaymentPlanWrapper paymentPlanWrapper = new RES_PaymentPlanWrapper();
        List<RES_PaymentPlanWrapper.PlanInstallment> installmentsWrapper = new List<RES_PaymentPlanWrapper.PlanInstallment>();
        List<RES_PaymentPlanWrapper.PaymentPlanAssignment> assignmentsWrapper = new List<RES_PaymentPlanWrapper.PaymentPlanAssignment>();
        for(Product2 paymentPlan : paymentPlans){
            paymentPlanWrapper.Change_Indicator = triggerContext;
            paymentPlanWrapper.RES_Product_External_ID = (paymentPlan.RES_Product_External_ID__c != null) ? paymentPlan.RES_Product_External_ID__c : ''; 
            paymentPlanWrapper.ProductName = paymentPlan.Name;
            paymentPlanWrapper.RES_No_of_Years = (paymentPlan.RES_No_of_Years__c != null) ? (Integer) paymentPlan.RES_No_of_Years__c : 0;
            paymentPlanWrapper.AvailabilityDate = (paymentPlan.AvailabilityDate != null) ? paymentPlan.AvailabilityDate.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'', 'UTC') : '';
            paymentPlanWrapper.DiscontinuedDate = (paymentPlan.RES_Validity_End_Date__c != null) ? DateTime.newInstanceGmt(paymentPlan.RES_Validity_End_Date__c, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'', 'UTC') : '';
            paymentPlanWrapper.RES_Approval_Status = (paymentPlan.RES_Approval_Status__c != null) ? paymentPlan.RES_Approval_Status__c : '';
            paymentPlanWrapper.RES_Status_Role_description = (paymentPlan.RES_Status_Role_Description__c != null) ? paymentPlan.RES_Status_Role_Description__c : '';
            paymentPlanWrapper.RES_Status_Role = (paymentPlan.RES_Status_Role__c != null) ? paymentPlan.RES_Status_Role__c : '';
            paymentPlanWrapper.RES_Note = (paymentPlan.RES_Note__c != null) ? paymentPlan.RES_Note__c : '';
            paymentPlanWrapper.RES_No_of_Months = (paymentPlan.RES_No_of_Months__c != null) ? (Integer) paymentPlan.RES_No_of_Months__c : 0;
            paymentPlanWrapper.RES_Review = (paymentPlan.RES_Review__c != null) ? paymentPlan.RES_Review__c : '';
            paymentPlanWrapper.RES_DSOP_NOTE = '';
            paymentPlanWrapper.RES_SLSD_NOTE = '';
            paymentPlanWrapper.RES_CDO_NOTE = '';
            paymentPlanWrapper.RES_CFO_NOTE = '';
            paymentPlanWrapper.RES_Z_TIME = paymentPlan.CreatedDate.format('HH:mm:ss');
            paymentPlanWrapper.RES_Z_DATE = paymentPlan.CreatedDate.format('yyyy-MM-dd');
            paymentPlanWrapper.RES_Z_ERNAM = paymentPlan.CreatedBy.Alias;
            paymentPlanWrapper.RES_Z_RBEAR = paymentPlan.LastModifiedBy.Alias;
            paymentPlanWrapper.RES_Z_DBEAR = paymentPlan.LastModifiedDate.format('yyyy-MM-dd');
            paymentPlanWrapper.RES_Z_TBEAR = paymentPlan.LastModifiedDate.format('HH:mm:ss');
            paymentPlanIds.add(paymentPlan.Id);
        }
        
        List<ProductRelatedComponent> childComponents = new RES_ProductRelatedComponentDAOLayer().getComponentsByParentProducts(paymentPlanIds);
        if(!childComponents.isEmpty()){
            for(ProductRelatedComponent prc : childComponents){
                RES_PaymentPlanWrapper.PlanInstallment installment = new RES_PaymentPlanWrapper.PlanInstallment();
                installment.Change_Indicator = triggerContext;
                installment.RES_Product_External_ID = paymentPlanWrapper.RES_Product_External_ID;
                installment.RES_Sequence = (prc.ChildProduct.RES_Sequence__c != null) ? (Integer) prc.ChildProduct.RES_Sequence__c : 0;
      			installment.RES_Installment_Payment_Type = (prc.ChildProduct.RES_Installment_Payment_Type__c  != null) ? prc.ChildProduct.RES_Installment_Payment_Type__c : '';
      			installment.Name = prc.ChildProduct.Name;
      			installment.RES_Installment_Percentage = (prc.ChildProduct.RES_Installment_Percentage__c != null) ? (Decimal) prc.ChildProduct.RES_Installment_Percentage__c : 0;
      			installment.RES_POC_Percentage = (prc.ChildProduct.RES_POC_Percentage__c != null) ? (Decimal) prc.ChildProduct.RES_POC_Percentage__c : 0;
      			installment.RES_Installment_Amount = (prc.ChildProduct.RES_Installment_Amount__c != null) ? (Decimal) prc.ChildProduct.RES_Installment_Amount__c : 0;
      			installment.Condition_Months = (prc.ChildProduct.RES_Condition_Months__c != null) ? (Integer) prc.ChildProduct.RES_Condition_Months__c : 0;
      			installment.Condition_Days = (prc.ChildProduct.RES_Condition_Days__c != null) ? (Integer) prc.ChildProduct.RES_Condition_Days__c : 0;
      			installment.Condition_Type = (prc.ChildProduct.RES_Condition_Type__c != null) ? prc.ChildProduct.RES_Condition_Type__c : '';
            	installmentsWrapper.add(installment);
            }
            paymentPlanWrapper.RES_Plan_Installments = (installmentsWrapper != null) ? installmentsWrapper : new List<RES_PaymentPlanWrapper.PlanInstallment>();
        }
        List<ProductRelatedComponent> parentProducts = new RES_ProductRelatedComponentDAOLayer().getPaymentPlanAssignments(paymentPlanIds);
        if(!parentProducts.isEmpty()){
            for(ProductRelatedComponent prc : parentProducts){
                RES_PaymentPlanWrapper.PaymentPlanAssignment assignment = new RES_PaymentPlanWrapper.PaymentPlanAssignment();
                assignment.Change_Indicator = triggerContext;
                assignment.RES_Product_External_ID = paymentPlanWrapper.RES_Product_External_ID;
                assignment.RES_Business_Entity = (prc.ParentProduct.RES_Business_Entity__c != null) ? prc.ParentProduct.RES_Business_Entity__r.RES_Business_Entity_Id__c : '';
      			assignment.RES_Construction_Phase = (prc.ParentProduct.RES_Construction_Phase__c != null) ? prc.ParentProduct.RES_Construction_Phase__c : '';
      			assignment.RES_Project = (prc.ParentProduct.RES_Business_Entity__c != null) ? prc.ParentProduct.RES_Business_Entity__r.Name : '';
      			assignment.RES_UnitId = (prc.ParentProduct.RES_Product_External_ID__c != null) ? prc.ParentProduct.RES_Product_External_ID__c : ''; 
      			assignment.Company_Code = (prc.ParentProduct.RES_Company_Code__c != null) ? prc.ParentProduct.RES_Company_Code__c : '';
            	assignmentsWrapper.add(assignment);
            }
            paymentPlanWrapper.RES_Payment_Plan_Assignments = (assignmentsWrapper != null) ? assignmentsWrapper : new List<RES_PaymentPlanWrapper.PaymentPlanAssignment>();
        }
        system.debug('JSON ==> ' + JSON.serializePretty(paymentPlanWrapper));
        return JSON.serializePretty(paymentPlanWrapper);
    }

    private static Boolean processResponse(
        String responseBody,
        RES_PaymentPlanIntegrationService service,
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
                'Payment_Plan',
                '',
                errorMessage,
                JSON.serialize(service.getHeaders()),
                objectType,
                recordId,
                String.valueOf(service.getRequestBody()),
                service.getRequestMethod(),
                'Payment_Plan',
                service.getRetryCount(),
                'Client Side'
            );
            RES_ResponseWrapper.logError(log);
        }

        return isSuccess;
    }

    public static void syncPaymentPlans(List<Product2> paymentPlans, String requestMethod, String triggerContext) {
        RES_PaymentPlanIntegrationService service = new RES_PaymentPlanIntegrationService(requestMethod);
        String body = service.hydrateRequestBody(paymentPlans, triggerContext);
        executeSync(service, body, paymentPlans[0].Id, 'Product2');
    }

    private static void executeSync(RES_PaymentPlanIntegrationService service, String body, Id recordId, String objectType) {
        service.setBody(body);
        service.setRecordId(String.valueOf(recordId));

        try {
            RES_IntegrationResponse response = service.sendRequest();
            System.debug(
                'Payment Plan Integration Response | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );

            Boolean isSuccess = processResponse(response.responseBody, service, recordId, objectType);

            if (isSuccess) {
                SObject toUpdate = Schema.getGlobalDescribe().get(objectType).newSObject(recordId);
                toUpdate.put('RES_Last_Sync_DateTime__c', System.now());
                Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            }

        } catch (Exception e) {
            System.debug('Exception occurred while calling the Payment Plan Integration Service: ' + e.getMessage() + e.getStackTraceString());
        }
    }
}