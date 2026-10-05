/** Blocks a Residential Sales (unit) Product2 from being set Active or its RES_Unit_Status__c set to Available unless the Service Charge Rate attribute override (ProductAttributeDefinition, DeveloperName driven by the RES_Service_Charge_Rate_Attribute Custom Label since it differs by org) is configured on that product. Other Product2 record types (Residential Payment Plan, Residential Installment, Commercial/Retail/Speciality Leasing) are not units and are exempt. */
public without sharing class RES_ProductSCRateValidation {

    private static final String SERVICE_CHARGE_RATE_ATTRIBUTE = Label.RES_Service_Charge_Rate_Attribute;
    private static final String AVAILABLE_STATUS = 'Available';
    private static final String RESIDENTIAL_SALES_RECORD_TYPE = 'RES_Residential_Sales';
    private static final Id RESIDENTIAL_SALES_RECORD_TYPE_ID = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName()
        .get(RESIDENTIAL_SALES_RECORD_TYPE)?.getRecordTypeId();
    private static final String ERROR_MESSAGE = 'This product\'s Service Charge Rate attribute override is not configured, so it cannot be set Active or its Unit Status set to Available.';

    @TestVisible
    private static Boolean turningActive(Product2 newProduct, Product2 oldProduct) {
        return newProduct.IsActive == true && oldProduct.IsActive != true;
    }

    @TestVisible
    private static Boolean turningAvailable(Product2 newProduct, Product2 oldProduct) {
        return newProduct.RES_Unit_Status__c == AVAILABLE_STATUS && oldProduct.RES_Unit_Status__c != AVAILABLE_STATUS;
    }

    public static void validate(List<Product2> newProducts, Map<Id, Product2> oldMap) {
        if (oldMap == null || RESIDENTIAL_SALES_RECORD_TYPE_ID == null) {
            return;
        }

        Set<Id> productIdsToCheck = new Set<Id>();
        for (Product2 newProduct : newProducts) {
            if (newProduct.RecordTypeId != RESIDENTIAL_SALES_RECORD_TYPE_ID) {
                continue;
            }
            Product2 oldProduct = oldMap.get(newProduct.Id);
            if (oldProduct == null) {
                continue;
            }
            if (turningActive(newProduct, oldProduct) || turningAvailable(newProduct, oldProduct)) {
                productIdsToCheck.add(newProduct.Id);
            }
        }

        if (productIdsToCheck.isEmpty()) {
            return;
        }

        Set<Id> productsWithServiceChargeRate = new Set<Id>();
        for (ProductAttributeDefinition pad : [
            SELECT Product2Id
            FROM ProductAttributeDefinition
            WHERE Product2Id IN :productIdsToCheck
                AND AttributeDefinition.DeveloperName = :SERVICE_CHARGE_RATE_ATTRIBUTE
                AND DefaultValue != null
        ]) {
            productsWithServiceChargeRate.add(pad.Product2Id);
        }

        for (Product2 newProduct : newProducts) {
            if (productIdsToCheck.contains(newProduct.Id) && !productsWithServiceChargeRate.contains(newProduct.Id)) {
                newProduct.addError(ERROR_MESSAGE);
            }
        }
    }
}
