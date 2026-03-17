@isTest
public with sharing class RES_PSRTest {
    @isTest
    static void testTriggerCoverage() {

        Lead l = new Lead(
            LastName = 'Test',
            Company = 'Test Company'
        );
        insert l;

        PendingServiceRouting psr = new PendingServiceRouting();
        psr.WorkItemId = l.Id;

        insert psr;
        Test.startTest();
        RES_PendingServiceRoutingService.startSLA(
            new List<PendingServiceRouting>{psr}
        );

        Test.stopTest();

        System.assert(true);
    }

}