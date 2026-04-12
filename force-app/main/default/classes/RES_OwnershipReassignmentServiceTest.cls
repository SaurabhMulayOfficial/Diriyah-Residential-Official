@isTest
private class RES_OwnershipReassignmentServiceTest {

    @isTest
    static void testOwnershipReassignment() {
        User u = RES_TestDataFactory.createSalesRepUser();
        Lead l = new Lead(
                LastName = 'Test Lead',
                Company = 'Test Company',
                Status = 'New',
                OwnerId =UserInfo.getUserId(),
                MobilePhone ='+1424124214'
            );

        System.runAs(u){
            insert l;
        }
        
        Test.startTest();
        RES_Ownership_Reassignment_Event__e eventMsg = new RES_Ownership_Reassignment_Event__e(
            RES_LeadId__c = l.Id,
            RES_OwnerId__c = u.Id
        );

        EventBus.publish(eventMsg);
        Test.stopTest(); 

        Lead updatedLead = [SELECT OwnerId, RES_Bypass_Assignment_Rules__c 
                            FROM Lead 
                            WHERE Id = :l.Id];

        System.assertEquals(u.Id, updatedLead.OwnerId);
        System.assertEquals(true, updatedLead.RES_Bypass_Assignment_Rules__c);
    }
}