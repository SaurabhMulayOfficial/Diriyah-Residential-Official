@IsTest
private class RES_PaymentPlanExpiryInvocableTest {

    @IsTest
    static void runBatchLaunchesThePaymentPlanExpiryBatch() {
        Test.startTest();
        RES_PaymentPlanExpiryInvocable.runBatch();
        Test.stopTest();

        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob
            WHERE JobType = 'BatchApex' AND ApexClass.Name = 'RES_PaymentPlanExpiryBatch'
        ], 'The invocable must enqueue exactly one RES_PaymentPlanExpiryBatch job');
    }
}
