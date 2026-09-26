/**
 * @description
 * Generic Queueable Apex class responsible for executing integration
 * synchronizations asynchronously.
 *
 * The class accepts a generic List<SObject> along with a service name
 * and delegates processing to the appropriate integration service.
 *
 * Currently supported integrations:
 * - Contract_Sync  -> RES_ContractIntegrationService
 * - Account_Sync   -> RES_AccountIntegrationService
 *
 * Database.AllowsCallouts is implemented because the delegated
 * integration services may perform HTTP callouts.
 *
 * @author
 * Saurabh Mulay
 */

public with sharing class RES_IntegrationQueueable implements Queueable, Database.AllowsCallouts {
    private List<SObject> records;
    private String serviceName;
    private String requestMethod;
    private String triggerContext;

    public RES_IntegrationQueueable(List<SObject> records,String serviceName,String requestMethod, String triggerContext) {
        this.records = records;
        this.serviceName = serviceName;
        this.requestMethod = requestMethod;
        this.triggerContext = triggerContext;
    }

    public void execute(QueueableContext context) {
        if (records == null || records.isEmpty()) {
            return;
        }

        if (serviceName == 'Sales_Contract_Creation') {
            List<Contract> contracts = new List<Contract>();
            for (SObject record : records) {
                contracts.add((Contract) record);
            }
            RES_ContractIntegrationService.syncContracts(contracts, requestMethod);
        }

        else if (serviceName == 'Sales_Contract_Update') {
            List<Contract> contracts = new List<Contract>();
            for (SObject record : records) {
                contracts.add((Contract) record);
            }
            RES_ContractUpdateIntegrationService.syncContracts(contracts, requestMethod);
        }

        else if (serviceName == 'Sales_Contract_Termination') {
            List<Contract> contracts = new List<Contract>();
            for (SObject record : records) {
                contracts.add((Contract) record);
            }
            RES_ContractTerminationIntService.syncContracts(contracts, requestMethod);
        }

        else if (serviceName == 'Payment_Plan') {
            List<RES_Payment_Plan__c> paymentPlans = new List<RES_Payment_Plan__c>();
            for (SObject record : records) {
                paymentPlans.add((RES_Payment_Plan__c) record);
            }
            RES_PaymentPlanIntegrationService.syncPaymentPlans(paymentPlans, requestMethod, triggerContext);
        }

        else if (serviceName == 'Installments') {
            List<RES_Installment__c> installments = new List<RES_Installment__c>();
            for (SObject record : records) {
                installments.add((RES_Installment__c) record);
            }
            RES_PaymentPlanIntegrationService.syncPaymentPlans(installments, requestMethod, triggerContext);
        }

        else if(serviceName == 'Account_Sync'){
            List<Account> accounts = new List<Account>();
            for (SObject record : records) {
                accounts.add((Account) record);
            }
            RES_AccountIntegrationService.syncAccounts(accounts, requestMethod, triggerContext);
        }
        
        else if(serviceName == 'Unit_Sync'){
            System.debug('### [RES_IntegrationQueueable] Unit_Sync executing | Records: ' + records.size() + ' | Context: ' + triggerContext);
            List<Product2> products = new List<Product2>();
            for (SObject record : records) {
                products.add((Product2) record);
            }
            RES_ProductIntegrationService.syncProducts(products, requestMethod, triggerContext);
        }
        
        else if(serviceName == 'ProductCategory_Sync'){
            List<ProductCategory> productCategories = new List<ProductCategory>();
            for (SObject record : records) {
                productCategories.add((ProductCategory) record);
            }
            RES_ProductCategoryIntegrationService.syncProductCategories(productCategories, requestMethod, triggerContext);
        }
        
        else if(serviceName == 'Measurement_Sync'){
            List<RES_Measurement__c> measurements = new List<RES_Measurement__c>();
            for (SObject record: records){
                measurements.add((RES_Measurement__c) record);
            }
            RES_ProductCategoryIntegrationService.syncMeasurements(measurements, requestMethod, triggerContext);   
        }
        
        else if(serviceName == 'Measurement_Sync_Catalog'){
            List<RES_Measurement__c> measurements = new List<RES_Measurement__c>();
            for (SObject record: records){
                measurements.add((RES_Measurement__c) record);
            }
            RES_ProductCatalogIntegrationService.syncMeasurementsWithProductCatalog(measurements, requestMethod, triggerContext);   
        }
        
        else if(serviceName == 'ProductCatalog_Sync'){
            List<ProductCatalog> productCatalogs = new List<ProductCatalog>();
            for (SObject record : records) {
                productCatalogs.add((ProductCatalog) record);
            }
            RES_ProductCatalogIntegrationService.syncProductCatalogs(productCatalogs, requestMethod, triggerContext);
        }
    }
}