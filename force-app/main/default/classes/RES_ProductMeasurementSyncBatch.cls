/**
 * @description Daily job (DIR-1797). A measurement becoming active or expiring on a date boundary involves no record save,
 *              so the trigger path never sees it. This batch re-syncs every product that has a tracked measurement whose
 *              From or To date is yesterday or today.
 *
 *              Schedule (daily 00:10):  System.schedule('RES Product Measurement Sync', '0 10 0 * * ?', new RES_ProductMeasurementSyncBatch());
 *              Called from: Salesforce scheduler. Delegates to RES_ProductMeasurementSyncService.
 */
public without sharing class RES_ProductMeasurementSyncBatch implements Database.Batchable<SObject>, Schedulable {

    private static final Integer BATCH_SIZE = 200;

    /** When true, processes EVERY product that has a tracked measurement (one-off backfill), not just date-boundary ones. */
    private final Boolean fullSync;

    public RES_ProductMeasurementSyncBatch() {
        this(false);
    }

    public RES_ProductMeasurementSyncBatch(Boolean fullSync) {
        this.fullSync = fullSync == true;
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new RES_ProductMeasurementSyncBatch(), BATCH_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Set<String> measurementTypes = RES_ProductMeasurementSyncService.getTrackedTypes();
        RES_Product2DAOLayer dao = new RES_Product2DAOLayer();
        if (fullSync) {
            return dao.getProductsWithMeasurementsLocator(measurementTypes);
        }
        Date toDate = RES_ProductMeasurementSyncService.today();
        return dao.getProductsWithMeasurementBoundaryLocator(measurementTypes, toDate.addDays(-1), toDate);
    }

    public void execute(Database.BatchableContext bc, List<Product2> scope) {
        Set<Id> productIds = new Set<Id>();
        for (Product2 p : scope) {
            productIds.add(p.Id);
        }
        RES_ProductMeasurementSyncService.syncProducts(productIds);
    }

    public void finish(Database.BatchableContext bc) {}
}
