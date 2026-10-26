/**
 * @description Product2 service: detects field changes and publishes Unit_Sync platform events to SAP, and defaults
 *              validity dates before save.
 * @author      Roshan Jambhule
 * @date        2025
 */
public with sharing class RES_ProductService {
    @TestVisible
    private static final Date DISCONTINUED_DEFAULT = Date.newInstance(3999, 12, 30);

    public RES_ProductService() {}

    /**
     * @description Defaults AvailabilityDate to today and DiscontinuedDate to 3999-12-30 when blank; existing values are
     *              never changed. Call after RES_ProductParentInheritanceService so a parent's dates win over the defaults.
     * @param products Trigger.new of a before insert / before update context
     */
    public static void applyDateDefaults(List<Product2> products) {
        if (products == null || products.isEmpty()) return;

        Date today = Date.today();
        for (Product2 p : products) {
            if (p.AvailabilityDate == null) {
                p.AvailabilityDate = today;
            }
            if (p.DiscontinuedDate == null) {
                p.DiscontinuedDate = DISCONTINUED_DEFAULT;
            }
        }
    }

    /**
     * @description Publishes Unit_Sync integration events for products with changed sync fields.
     *              Throws RES_IntegrationException when Unit_Sync MDT config is missing.
     */
    public static void syncProducts(List<Product2> products, Map<Id, Product2> oldMap) {
        System.debug('### [RES_ProductService] syncProducts | Products: ' + products.size() + ' | isInsert: ' + (oldMap == null));
        List<Product2> productsToSync = new List<Product2>();
        RES_SAP_Integration_Config__mdt productMDT = new RES_SAPIntegrationConfigDAO().getSAPIntegrationConfigByDeveloperName('Unit_Sync');
        System.debug('### [RES_ProductService] Unit_Sync MDT found: ' + (productMDT != null));

        if (productMDT == null || String.isBlank(productMDT.RES_Sync_Fields__c)) {
            System.debug('### [RES_ProductService] ERROR: Unit_Sync MDT missing or no sync fields');
            throw new RES_IntegrationException(
                'SAP Integration Config is Not available for "Unit Sync", create and provide at least 1 field for change.'
            );
        }

        List<String> syncFieldLst = productMDT.RES_Sync_Fields__c.split(',');
        Set<String> syncFields = new Set<String>();
        for (String field : syncFieldLst) {
            if (String.isNotBlank(field)) {
                syncFields.add(field.trim());
            }
        }

        for (Product2 p : products) {
            if (oldMap == null || isProductChanged(p, oldMap.get(p.Id), syncFields)) {
                productsToSync.add(p);
            }
        }

        String triggerContext = (oldMap == null ? 'I' : 'U');

        System.debug('### [RES_ProductService] productsToSync count: ' + productsToSync.size());
        if (productsToSync.isEmpty()) {
            System.debug('### [RES_ProductService] No changed products — skipping event publish');
            return;
        }

        List<RES_Integration_Request__e> integrationRequestEventList = new List<RES_Integration_Request__e>();
        for (Product2 p : productsToSync) {
            RES_Integration_Request__e req = new RES_Integration_Request__e();
            req.RES_RecordIds__c          = String.valueOf(p.Id);
            req.RES_Request_Method__c     = 'GET';
            req.RES_Triggering_Context__c = triggerContext;
            req.RES_Service_Name__c       = 'Unit_Sync';
            integrationRequestEventList.add(req);
        }

        try {
            if (integrationRequestEventList.size() > 0) {
                System.debug('### [RES_ProductService] Publishing ' + integrationRequestEventList.size() + ' RES_Integration_Request__e events');
                EventBus.publish(integrationRequestEventList);
                System.debug('### [RES_ProductService] Events published successfully');
            }
        } catch (Exception e) {
            System.debug('### [RES_ProductService] Exception Firing Integration Request Event: ' + e.getMessage());
        }
    }

    /**
     * @description Returns true when any configured sync field value differs between old and new records.
     *              Returns true unconditionally when oldRecord is null (INSERT context).
     */
    @TestVisible
    private static Boolean isProductChanged(Product2 newRecord, Product2 oldRecord, Set<String> syncFields) {
        if (oldRecord == null) {
            return true;
        }

        for (String fieldName : syncFields) {
            try {
                Object newValue = newRecord.get(fieldName);
                Object oldValue = oldRecord.get(fieldName);
                if (String.valueOf(newValue) != String.valueOf(oldValue)) {
                    return true;
                }
            } catch (SObjectException e) {
                System.debug('Invalid sync field "' + fieldName + '" for Product2, skipping: ' + e.getMessage());
            }
        }
        return false;
    }

    public static void setExternalID(List<Product2> productsLst){
        List<Product2> paymentPlan = new RES_Product2DAOLayer().getLatestPaymentPlan();
        if(!paymentPlan.isEmpty()){
            String nextExternalId = getNextExternalId(paymentPlan[0].RES_Product_External_ID__c);
            String previousExternalId = '';
            Integer count = 1;
            Id paymentPlanRT = Schema.SObjectType.Product2
                                 .getRecordTypeInfosByDeveloperName()
                                 .get('RES_Residential_Payment_Plan').getRecordTypeId();
            for(Product2 product : productsLst){
                if(product.RecordTypeId == paymentPlanRT){
                    if(count == 1){
                        product.RES_Product_External_ID__c = nextExternalId;
                    }
                    else{
                        product.RES_Product_External_ID__c = getNextExternalId(previousExternalId);
                    }
                    previousExternalId = product.RES_Product_External_ID__c;
                    count++;
                }
            }
        }
    }
    
    public static String getNextExternalId(String latestExternalId){
        String numericPart = latestExternalId.substring(1);
        Integer nextNum = Integer.valueOf(numericPart) + 1;   
        String nextExternalId = 'S' + String.valueOf(nextNum).leftPad(numericPart.length(), '0');
        return nextExternalId;
    }
    
    public static void updateNumberOfMonths(List<Product2> productsLst, Map<Id, Product2> oldMap){
        for (Product2 productObj : productsLst) {
            productObj.RES_No_of_Months__c = (productObj.RES_No_of_Years__c != oldMap.get(productObj.Id).RES_No_of_Years__c) ? (productObj.RES_No_of_Years__c == null ? null : productObj.RES_No_of_Years__c * 12) : productObj.RES_No_of_Months__c;
        }
    }
}
