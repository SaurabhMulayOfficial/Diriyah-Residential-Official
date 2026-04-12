@IsTest
public class RES_PSRTest {

    @IsTest
    static void testPSRTriggerLogic() {

        Group testQueue = new Group(
            Name = 'Test Queue',
            Type = 'Queue'
        );

        insert testQueue;

        Lead testLead = new Lead(
            LastName = 'Test PSR Lead',
            Company  = 'Test Corp',
            Status   = '01',
            mobilePhone = '+1234567890'
        );

        insert testLead;

        PendingServiceRouting psr = new PendingServiceRouting(
            RoutingType       = 'QueueBased',
            WorkItemId        = testLead.Id
        );

        List<pendingServiceRouting> psrList = new List<PendingServiceRouting>{psr};
        List<RES_PendingServiceRoutingService.FlowInput> inputs = new List<RES_PendingServiceRoutingService.FlowInput>();

        RES_PendingServiceRoutingService.FlowInput f = new RES_PendingServiceRoutingService.FlowInput();

        f.workItemId = testLead.Id;
        f.groupId = testQueue.Id;
        inputs.add(f);

        Test.startTest();
        RES_PendingServiceRoutingService.startSLAFromFlow(inputs);
        Test.stopTest();
    }
}