/**
 * Class Name   : RES_QuoteLineItemProductHandler
 * Description  : Handler for QuoteLineItem trigger to populate RES_Product__c
 *                on Quote when a Residential Unit product is added.
 *
 * Usage:
 *      RES_QuoteLineItemProductHandler.populateQuoteProduct(Trigger.new);
 */
public with sharing class RES_QuoteLineItemProductHandler {

    private static final String RESIDENTIAL_UNIT_RT = 'RES_Residential_Sales';

    private static final RES_Product2DAOLayer productDAO = new RES_Product2DAOLayer();
    private static final RES_QuoteLineItemDAO quoteLineItemDAO = new RES_QuoteLineItemDAO();
    private static final RES_QuoteDAOLayer quoteDAO = new RES_QuoteDAOLayer();

    /**
     * Populates RES_Product__c on Quote when QuoteLineItem is inserted
     * with a Residential Unit product.
     *
     * @param newQuoteLineItems List of newly inserted QuoteLineItems
     */
    public static void populateQuoteProduct(List<QuoteLineItem> newQuoteLineItems) {
        try {
            if (newQuoteLineItems == null || newQuoteLineItems.isEmpty()) {
                return;
            }

            Set<Id> productIds = new Set<Id>();
            Set<Id> quoteIds = new Set<Id>();
            Map<Id, Id> quoteToProductMap = new Map<Id, Id>();

            for (QuoteLineItem qli : newQuoteLineItems) {
                if (qli.Product2Id != null && qli.QuoteId != null) {
                    productIds.add(qli.Product2Id);
                    quoteIds.add(qli.QuoteId);
                }
            }

            if (productIds.isEmpty() || quoteIds.isEmpty()) {
                return;
            }

            List<Product2> products = productDAO.getProductsWithRecordTypeByIds(productIds);

            Map<Id, Product2> productsById = new Map<Id, Product2>();
            for (Product2 product : products) {
                if (product.RecordType != null &&
                    product.RecordType.DeveloperName == RESIDENTIAL_UNIT_RT) {
                    productsById.put(product.Id, product);
                }
            }

            if (productsById.isEmpty()) {
                return;
            }

            for (QuoteLineItem qli : newQuoteLineItems) {
                if (qli.Product2Id != null &&
                    qli.QuoteId != null &&
                    productsById.containsKey(qli.Product2Id)) {

                    if (!quoteToProductMap.containsKey(qli.QuoteId)) {
                        quoteToProductMap.put(qli.QuoteId, qli.Product2Id);
                    }
                }
            }

            if (quoteToProductMap.isEmpty()) {
                return;
            }

            List<Quote> quotesToUpdate = new List<Quote>();

            for (Id quoteId : quoteToProductMap.keySet()) {
                Quote quoteToUpdate = new Quote(
                    Id = quoteId,
                    RES_Product__c = quoteToProductMap.get(quoteId)
                );
                quotesToUpdate.add(quoteToUpdate);
            }

            if (!quotesToUpdate.isEmpty()) {
                Database.SaveResult[] saveResults = Database.update(
                    quotesToUpdate,
                    false,
                    AccessLevel.SYSTEM_MODE
                );
            }

        } catch (Exception e) {
            throw new QuoteLineItemProductException(
                'Failed to populate Quote Product: ' + e.getMessage(),
                e
            );
        }
    }

    /**
     * Clears or reassigns RES_Product__c on Quote when QuoteLineItem is deleted.
     * If the deleted product was the one referenced on Quote, it either clears
     * the field or reassigns to another Residential Unit if one exists.
     *
     * @param deletedQuoteLineItems List of deleted QuoteLineItems
     * @param oldQuoteLineItemMap Map of old QuoteLineItem values
     */
    public static void clearQuoteProduct(
        List<QuoteLineItem> deletedQuoteLineItems,
        Map<Id, QuoteLineItem> oldQuoteLineItemMap
    ) {
        try {
            if (deletedQuoteLineItems == null || deletedQuoteLineItems.isEmpty()) {
                return;
            }

            Set<Id> quoteIds = new Set<Id>();
            Set<Id> deletedProductIds = new Set<Id>();

            for (QuoteLineItem qli : deletedQuoteLineItems) {
                if (qli.QuoteId != null && qli.Product2Id != null) {
                    quoteIds.add(qli.QuoteId);
                    deletedProductIds.add(qli.Product2Id);
                }
            }

            if (quoteIds.isEmpty()) {
                return;
            }

            Map<Id, Quote> quotesById = quoteDAO.getQuotesByIds(quoteIds);

            List<QuoteLineItem> remainingQLIs = quoteLineItemDAO.getQuoteLineItemsByQuoteIds(quoteIds);

            Map<Id, List<QuoteLineItem>> qlisByQuoteId = new Map<Id, List<QuoteLineItem>>();
            Set<Id> remainingProductIds = new Set<Id>();

            for (QuoteLineItem qli : remainingQLIs) {
                if (qli.QuoteId != null && qli.Product2Id != null) {
                    if (!qlisByQuoteId.containsKey(qli.QuoteId)) {
                        qlisByQuoteId.put(qli.QuoteId, new List<QuoteLineItem>());
                    }
                    qlisByQuoteId.get(qli.QuoteId).add(qli);
                    remainingProductIds.add(qli.Product2Id);
                }
            }

            List<Product2> remainingProducts = new List<Product2>();
            if (!remainingProductIds.isEmpty()) {
                remainingProducts = productDAO.getProductsWithRecordTypeByIds(remainingProductIds);
            }

            Map<Id, Product2> residentialProductsById = new Map<Id, Product2>();
            for (Product2 product : remainingProducts) {
                if (product.RecordType != null &&
                    product.RecordType.DeveloperName == RESIDENTIAL_UNIT_RT) {
                    residentialProductsById.put(product.Id, product);
                }
            }

            List<Quote> quotesToUpdate = new List<Quote>();

            for (Id quoteId : quotesById.keySet()) {
                Quote currentQuote = quotesById.get(quoteId);

                if (currentQuote.RES_Product__c == null) {
                    continue;
                }

                if (deletedProductIds.contains(currentQuote.RES_Product__c)) {
                    Id replacementProductId = null;
                    List<QuoteLineItem> remainingForQuote = qlisByQuoteId.get(quoteId);

                    if (remainingForQuote != null) {
                        for (QuoteLineItem qli : remainingForQuote) {
                            if (residentialProductsById.containsKey(qli.Product2Id)) {
                                replacementProductId = qli.Product2Id;
                                break;
                            }
                        }
                    }

                    Quote quoteToUpdate = new Quote(
                        Id = quoteId,
                        RES_Product__c = replacementProductId
                    );
                    quotesToUpdate.add(quoteToUpdate);
                }
            }

            if (!quotesToUpdate.isEmpty()) {
                Database.SaveResult[] saveResults = Database.update(
                    quotesToUpdate,
                    false,
                    AccessLevel.SYSTEM_MODE
                );
            }

        } catch (Exception e) {
            throw new QuoteLineItemProductException(
                'Failed to clear Quote Product: ' + e.getMessage(),
                e
            );
        }
    }

    public class QuoteLineItemProductException extends Exception {}
}
