public with sharing class RES_OpportunityClosedLostService {

    @InvocableMethod(label='Release Opportunity Units')
    public static List<Output> releaseUnits(List<Input> inputs) {

        Output output = new Output();
        output.unitsReleased = false;
        if (inputs == null || inputs.isEmpty()) {
            return new List<Output>{ output };
        }
        try {
            // 1. Collect Opportunity Ids
            Set<Id> opportunityIds = new Set<Id>();
            for (Input inputRec : inputs) {
                if (inputRec != null && inputRec.opportunityId != null) {
                    opportunityIds.add(inputRec.opportunityId);
                }
            }
            if (opportunityIds.isEmpty()) {
                return new List<Output>{ output };
            }
            List<QuoteLineItem> quoteLineItems = new RES_QuoteLineItemDAO().getQuoteLineItemsByOpportunity(opportunityIds);
            Set<Id> productIds = new Set<Id>();
            for (QuoteLineItem qli : quoteLineItems) {
                if (qli.Product2Id != null) {
                    productIds.add(qli.Product2Id);
                }
            }
            List<Product2> products = new List<Product2>();
            if (!productIds.isEmpty()) {
                products =
                    new RES_Product2DAOLayer()
                        .getProductsByIds(productIds);
            }
            List<Quote> quotes = new RES_QuoteDAOLayer().getQuotesByOpportunityIds(opportunityIds);
            List<Quote> quotesToUpdate = new List<Quote>();
            for (Quote quote : quotes) {
                if (quote.Status != 'Cancelled') {
                    quote.Status = 'Cancelled';
                    quotesToUpdate.add(quote);
                }
            }

            if (!quotesToUpdate.isEmpty()) {
                Database.SaveResult[] quoteResults =
                    Database.update(
                        quotesToUpdate,
                        false,
                        AccessLevel.SYSTEM_MODE
                    );
                for (Integer i = 0; i < quoteResults.size(); i++) {
                    if (!quoteResults[i].isSuccess()) {
                        for (Database.Error error :
                            quoteResults[i].getErrors()) {
                            System.debug(
                                LoggingLevel.ERROR,
                                'Quote cancellation failed. Quote Id: '
                                + quotesToUpdate[i].Id
                                + ' | Error: '
                                + error.getMessage()
                            );
                        }
                    }
                }
            }

            if (products.isEmpty()) {
                return new List<Output>{ output };
            }

            List<Product2> productsToUpdate = new List<Product2>();
            for (Product2 product : products) {
                Boolean isChanged = false;
                if (
                    product.RES_Unit_Status__c == 'Soft Hold' ||
                    product.RES_Unit_Status__c == 'Hard Block'
                ) {
                    product.RES_Unit_Status__c = 'Available';
                    product.RES_Is_In_Soft_Hold_Extension__c = false;
                    product.RES_Soft_Hold_Start__c = null;
                    product.RES_Soft_Hold_Until__c = null;
                    isChanged = true;
                }
                if (product.RES_HardBlock_Start__c != null) {
                    product.RES_HardBlock_Start__c = null;
                    isChanged = true;
                }

                if (isChanged) {
                    productsToUpdate.add(product);
                }
            }
            
            if (!productsToUpdate.isEmpty()) {
                Database.SaveResult[] productResults =
                    Database.update(
                        productsToUpdate,
                        false,
                        AccessLevel.SYSTEM_MODE
                    );

                for (Integer i = 0; i < productResults.size(); i++) {
                    if (productResults[i].isSuccess()) {
                        output.unitsReleased = true;
                    } else {
                        for (Database.Error error :
                            productResults[i].getErrors()) {
                            System.debug(
                                LoggingLevel.ERROR,
                                'Product update failed. Product Id: '
                                + productsToUpdate[i].Id
                                + ' | Error: '
                                + error.getMessage()
                            );
                        }
                    }
                }
            }
            return new List<Output>{ output };
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'RES_OpportunityClosedLostService failed. '
                + 'Message: ' + ex.getMessage()
                + ' | Line: ' + ex.getLineNumber()
            );

            throw new AuraHandledException(
                'Error while releasing Units and cancelling Quotes: '
                + ex.getMessage()
            );
        }
    }


    public class Input {
        @InvocableVariable(required=true)
        public Id opportunityId;
    }


    public class Output {
        @InvocableVariable
        public Boolean unitsReleased;
    }
}