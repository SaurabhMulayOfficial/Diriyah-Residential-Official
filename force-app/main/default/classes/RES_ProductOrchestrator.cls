public without sharing class RES_ProductOrchestrator {
    public RES_ProductOrchestrator() {}

    public static void applySoftHold(List<Opportunity> OpportunityList){
        Set<Id> oppIds = new Set<Id>();
        for(Opportunity op: OpportunityList){
            oppIds.add(op.Id);
        }

        System.debug('Opportunities '+ oppIds.size());
        if(oppIds.size() <= 0)return;

        List<QuoteLineItem> quoteLineItems = new RES_QuoteLineItemDAO().getQuoteLineItemsByOpportunity(oppIds);
        System.debug('Quote Line Items '+ quoteLineItems.size());

        if(quoteLineItems.size() <= 0)return;
        Map<Id, Id> productBlockedBy = new Map<Id, Id>();
        for(QuoteLineItem qli: quoteLineItems){
            if(!productBlockedBy.containsKey(qli.Product2Id)){
                productBlockedBy.put(qli.Product2Id, qli.QuoteId);
            }
        }
        System.debug('Products Blocked By '+ productBlockedBy.size());
        List<QuoteLineItem> allRelatedQuoteLineItems = new RES_QuoteLineItemDAO().getQuoteLineItemsByProductIds(productBlockedBy.keySet());
        Set<Id> quotesIds = new Set<Id>();
        system.debug('All Related Quote Line Items: ' + allRelatedQuoteLineItems.size());
        for(QuoteLineItem qli: allRelatedQuoteLineItems){
            if(productBlockedBy.containsKey(qli.Product2Id) && qli.QuoteId != productBlockedBy.get(qli.Product2Id)){
                quotesIds.add(qli.QuoteId);
            }
        }
        System.debug('Quotes to Update '+ quotesIds.size());
        List<Quote> quotesToUpdate = new List<Quote>();
        for(Id quoteId: quotesIds){
            Quote q = new Quote(Id = quoteId);
            q.RES_Product_Soft_Held__c = true;
            quotesToUpdate.add(q);
        }
        System.debug('Quotes to Update '+ quotesToUpdate.size());
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