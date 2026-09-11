/*
 * Class Name  : RES_ProductSellingModelDAOLayer
 * Description : DAO layer for ProductSellingModel object.
 */
public without sharing class RES_ProductSellingModelDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ProductSellingModel';
    }

    public List<ProductSellingModel> getAllSellingModels() {
        String soql = 'SELECT Id, Name, SellingModelType, PricingTerm, PricingTermUnit ' +
                      'FROM ProductSellingModel LIMIT 2000';
        // Not cached: RES_UnifiedIngestionEngine creates new ProductSellingModel records and
        // then re-queries this same DAO method later in the same transaction (e.g. a later
        // batch chunk, or a second ingestion run). A cached "no models yet" result would go
        // stale the moment the first one is inserted, causing the engine to attempt a second
        // insert with the same SellingModelType and fail on the uniqueness constraint.
        return (List<ProductSellingModel>) executeQuery(soql, 'getAllSellingModels', false, null, AccessLevel.SYSTEM_MODE);
    }
}