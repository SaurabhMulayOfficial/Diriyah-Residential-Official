/*
 * Class Name  : RES_PricebookEntryDAOLayer
 * Description : DAO layer for PricebookEntry object.
 */
public without sharing class RES_PricebookEntryDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'PricebookEntry';
    }

    public List<PricebookEntry> getEntriesByBookAndProducts(Id bookId, Set<Id> productIds, Boolean hasSellingModel) {
        if (bookId == null || productIds == null || productIds.isEmpty()) return new List<PricebookEntry>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'bookId' => bookId, 'productIds' => productIds };
        List<String> fields = new List<String>{ 'Id', 'Product2Id', 'UnitPrice', 'IsActive' };
        if (hasSellingModel) {
            fields.add('ProductSellingModelId');
        }
        String soql = 'SELECT ' + String.join(fields, ', ') +
                      ' FROM PricebookEntry WHERE Pricebook2Id = :bookId AND Product2Id IN :productIds';
        return (List<PricebookEntry>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
    /**
    * Retrieves PricebookEntry Related To Product
    */
    public List<PricebookEntry> getPricebookEntryRelatedToProducts(Set<Id> productIdSet, Boolean isStandardPriceBook) {
        if (productIdSet == null || productIdSet.isEmpty()) {
            return new List<PricebookEntry>();
        }
        
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('productIdSet', productIdSet);
        bindVars.put('isStandardPriceBook', isStandardPriceBook);

        String soql = 'SELECT Id, Product2Id, Pricebook2Id, UnitPrice, IsActive, UseStandardPrice, ProductSellingModelId ' + 
                      'FROM PricebookEntry ' + 
                      'WHERE Product2Id IN : productIdSet AND ' + 
                      'Pricebook2.IsStandard =: isStandardPriceBook';
        return (List<PricebookEntry>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}