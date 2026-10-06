@IsTest
private class RES_IntegrationSyncControllerTest {

    @IsTest
    static void firesOneEventPerId() {
        Test.startTest();
        RES_IntegrationSyncController.SyncResult r = RES_IntegrationSyncController.fireIntegrationEvents(
            'Account_Sync', 'U', 'GET', '001000000000001AAA, 001000000000002AAA\n001000000000001AAA');
        Test.stopTest();
        System.assertEquals(2, r.eventsFired, 'Duplicates removed, one event per unique Id');
    }

    @IsTest
    static void rejectsBadInput() {
        String[][] bad = new String[][]{
            new String[]{ 'Nope', 'I', 'GET', '001000000000001AAA' },
            new String[]{ 'Account_Sync', 'X', 'GET', '001000000000001AAA' },
            new String[]{ 'Account_Sync', 'I', 'DELETE', '001000000000001AAA' },
            new String[]{ 'Account_Sync', 'I', 'GET', '' },
            new String[]{ 'Account_Sync', 'I', 'GET', 'abc' }
        };
        for (String[] a : bad) {
            try {
                RES_IntegrationSyncController.fireIntegrationEvents(a[0], a[1], a[2], a[3]);
                System.assert(false, 'Expected exception for ' + a);
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }
}
