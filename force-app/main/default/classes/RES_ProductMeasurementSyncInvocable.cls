/**
 * @description Flow entry point (DIR-1797) that launches RES_ProductMeasurementSyncBatch.
 *              Called from: flow RES_Scheduled_Product_Measurement_Sync (daily schedule-triggered flow).
 *              Exists because Apex schedules are org data and cannot be deployed; an active scheduled flow is metadata.
 */
public with sharing class RES_ProductMeasurementSyncInvocable {

    private static final Integer BATCH_SIZE = 200;

    @InvocableMethod(label = 'Run Product Measurement Sync Batch' description = 'Re-syncs measurement-derived Product2 fields for measurements starting or ending around today.')
    public static void runBatch() {
        Database.executeBatch(new RES_ProductMeasurementSyncBatch(), BATCH_SIZE);
    }
}
