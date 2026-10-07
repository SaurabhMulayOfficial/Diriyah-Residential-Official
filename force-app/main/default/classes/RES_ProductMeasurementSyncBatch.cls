/**
 * @description Daily job (DIR-1797). A measurement becoming active or expiring on a date boundary involves no record save,
 *              so the trigger path never sees it. This batch re-syncs every product that has a measurement whose
 *              From or To date is yesterday or today.
 *
 *              Scheduled daily by flow RES_Scheduled_Product_Measurement_Sync via RES_ProductMeasurementSyncInvocable.
 *              One-off full backfill: Database.executeBatch(new RES_ProductMeasurementSyncBatch(true), 200);
 *              Scope is RES_Measurement__c (not Product2) so this class does not depend on RES_Product2DAOLayer.
 *              Delegates to RES_ProductMeasurementSyncService.
 */
public without sharing class RES_ProductMeasurementSyncBatch implements Database.Batchable<SObject>, Schedulable {

    private static final Integer BATCH_SIZE = 200;

    /** When true, processes EVERY product that has a measurement (one-off backfill), not just date-boundary ones. */
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
        RES_MeasurementDAOLayer dao = new RES_MeasurementDAOLayer();
        if (fullSync) {
            return dao.getProductMeasurementsLocator();
        }
        Date toDate = RES_ProductMeasurementSyncService.today();
        return dao.getProductMeasurementsBoundaryLocator(toDate.addDays(-1), toDate);
    }

    public void execute(Database.BatchableContext bc, List<RES_Measurement__c> scope) {
        Set<Id> productIds = new Set<Id>();
        for (RES_Measurement__c m : scope) {
            productIds.add(m.RES_Product__c);
        }
        RES_ProductMeasurementSyncService.syncProducts(productIds);
    }

    public void finish(Database.BatchableContext bc) {}
}
