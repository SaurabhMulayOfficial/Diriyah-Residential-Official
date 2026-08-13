/**
 * ==============================================================================
 * Class Name    : RES_ProductOrchestrator
 * Description   : Service class responsible for orchestrating Product/Unit
 *                 Soft Hold processing for Opportunities.
 *
 *                 Identifies the Products/Units associated with the provided
 *                 Opportunities through Quote Line Items and applies a Soft Hold
 *                 to those Units.
 *
 *                 The service also identifies other Quotes containing the same
 *                 Products/Units and marks them as Product Soft Held.
 *
 *                 The Soft Hold duration is determined from the
 *                 Soft_Hold_Window custom label and the default Business Hours
 *                 configuration.
 *
 *                 The associated Unit is updated with the Soft Hold start date,
 *                 Soft Hold expiry date, and the Quote responsible for the hold.
 *
 * Author        : Saurabh Mule
 * Company       : Globant Inc
 * Created Date  : Aug 13, 2026
 * Version       : 1.0
 * ============================================================================== 
 * **/
public without sharing class RES_ProductOrchestrator {
    public RES_ProductOrchestrator() {}

    public static void applySoftHold(List<Opportunity> OpportunityList){
        Set<Id> oppIds = new Set<Id>();
        for(Opportunity op: OpportunityList){
            oppIds.add(op.Id);
        }
        if(oppIds.size() <= 0)return;

        List<QuoteLineItem> quoteLineItems = new RES_QuoteLineItemDAO().getQuoteLineItemsByOpportunity(oppIds);

        if(quoteLineItems.size() <= 0)return;
        Map<Id, Id> productBlockedBy = new Map<Id, Id>();
        for(QuoteLineItem qli: quoteLineItems){
            if(!productBlockedBy.containsKey(qli.Product2Id)){
                productBlockedBy.put(qli.Product2Id, qli.QuoteId);
            }
        }
        List<QuoteLineItem> allRelatedQuoteLineItems = new RES_QuoteLineItemDAO().getQuoteLineItemsByProductIds(productBlockedBy.keySet());
        Set<Id> quotesIds = new Set<Id>();
        for(QuoteLineItem qli: allRelatedQuoteLineItems){
            if(productBlockedBy.containsKey(qli.Product2Id) && qli.QuoteId != productBlockedBy.get(qli.Product2Id)){
                quotesIds.add(qli.QuoteId);
            }
        }
        List<Quote> quotesToUpdate = new List<Quote>();
        for(Id quoteId: quotesIds){
            Quote q = new Quote(Id = quoteId);
            q.RES_Product_Soft_Held__c = true;
            quotesToUpdate.add(q);
        }

        if(quotesToUpdate.size() > 0){
            try{
                Database.update(quotesToUpdate, false, AccessLevel.SYSTEM_MODE);
            }
            catch(Exception e){
                System.debug('Error occurred while updating quotes: ' + e.getMessage());
            }
        }

        Integer softHoldWindow = 8;
        String softHoldWindowLabel = SYSTEM.Label.Soft_Hold_Window;
        if(String.isNotBlank(softHoldWindowLabel)){
            softHoldWindow = Integer.valueOf(softHoldWindowLabel);
        }

        List<BusinessHours> businessHourLst = new RES_BusinessHoursDAOLayer().getDefaultBusinessHours();
        List<Product2> productsToUpdate = new List<Product2>();
        for(Id productId: productBlockedBy.keySet()){
            Product2 p = new Product2(Id = productId);
            p.RES_Unit_Status__c = 'Soft Hold';
            p.RES_Soft_Hold_Start__c = System.now();
            Long interval = (Long)softHoldWindow * 60 * 60 * 1000;
            p.RES_Soft_Hold_Until__c = BusinessHours.add(businessHourLst[0].Id, System.now(), interval);
            p.RES_Reserved_By_Quote__c = productBlockedBy.get(productId);
            productsToUpdate.add(p);
        }

        try{
            Database.update(productsToUpdate, false, AccessLevel.SYSTEM_MODE);
        }
        catch(Exception e){
            System.debug('Error occurred while updating products: ' + e.getMessage());
        }
    }
}