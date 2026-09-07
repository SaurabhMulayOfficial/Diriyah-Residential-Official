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

    public RES_IntegrationQueueable(List<SObject> records,String serviceName,String requestMethod) {
        this.records = records;
        this.serviceName = serviceName;
        this.requestMethod = requestMethod;
    }

    public void execute(QueueableContext context) {
        if (records == null || records.isEmpty()) {
            return;
        }

        if (serviceName == 'Contract_Sync') {
            List<Contract> contracts = new List<Contract>();
            for (SObject record : records) {
                contracts.add((Contract) record);
            }
            RES_ContractIntegrationService.syncContracts(contracts, requestMethod);
        }

        else if(serviceName == 'Account_Sync'){
            List<Account> accounts = new List<Account>();
            for (SObject record : records) {
                accounts.add((Account) record);
            }
            RES_AccountIntegrationService.syncAccounts(accounts, requestMethod);
        }
        
        else if(serviceName == 'Product_Sync'){
            List<Product2> products = new List<Product2>();
            for (SObject record : records) {
                products.add((Product2) record);
            }
            RES_ProductIntegrationService.syncProducts(products, requestMethod);
        }
        
        else if(serviceName == 'ProductCategory_Sync'){
            List<ProductCategory> productCategories = new List<ProductCategory>();
            for (SObject record : records) {
                productCategories.add((ProductCategory) record);
            }
            RES_ProductCategoryIntegrationService.syncProductCategories(productCategories, requestMethod);
        }
        
        else if(serviceName == 'ProductCatalog_Sync'){
            List<ProductCatalog> productCatalogs = new List<ProductCatalog>();
            for (SObject record : records) {
                productCatalogs.add((ProductCatalog) record);
            }
            RES_ProductCatalogIntegrationService.syncProductCatalogs(productCatalogs, requestMethod);
        }
    }
}