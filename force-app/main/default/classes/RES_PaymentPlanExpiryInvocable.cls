/**
 * @description Flow entry point that launches RES_PaymentPlanExpiryBatch.
 *              Called from: flow RES_Scheduled_Payment_Plan_Expiry (daily schedule-triggered flow).
 *              Exists because Apex schedules are org data and cannot be deployed; an active scheduled flow is metadata.
 */
public with sharing class RES_PaymentPlanExpiryInvocable {

    private static final Integer BATCH_SIZE = 200;

    @InvocableMethod(label = 'Run Payment Plan Expiry Batch' description = 'Removes expired Payment Plans from the Units they are tagged to and keeps one default Payment Plan per Unit.')
    public static void runBatch() {
        Database.executeBatch(new RES_PaymentPlanExpiryBatch(), BATCH_SIZE);
    }
}
