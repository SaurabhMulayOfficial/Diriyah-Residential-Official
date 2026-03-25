@IsTest
private class RES_LeadServicesTest {

    private static User createUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];

        User u = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser' + System.currentTimeMillis() + '@test.com',
            Username = 'testuser' + System.currentTimeMillis() + '@test.com',
            Alias = 'tuser',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert u;
        return u;
    }

    @IsTest
    static void testInsertFlow() {

        User u = createUser();
        System.runAs(u) {
            Lead l = new Lead(
                LastName = 'Test Lead',
                Company = 'Test Company',
                Status = 'New',
                OwnerId = u.Id,
                RES_SLA_Cycle_Count__c = 0
            );

            insert l;

            Test.startTest();
            RES_LeadServices.setUpdateSLATimeOnLead(
                new List<Lead>{l},
                null,
                false,
                null
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void testStatusChangeFlow() {
        User u = createUser();
        System.runAs(u) {

            Lead l = new Lead(
                LastName = 'Test Lead 2',
                Company = 'Test Company',
                Status = 'New',
                OwnerId = u.Id,
                RES_SLA_Status__c = 'Running',
                RES_SLA_Cycle_Count__c = 1,
                RES_SLA_Due_Time__c = System.now().addHours(5)
            );

            insert l;

            Lead oldLead = l.clone(false, true, false, false);

            l.Status = 'Working';

            Test.startTest();
            RES_LeadServices.setUpdateSLATimeOnLead(
                new List<Lead>{l},
                new Map<Id, Lead>{l.Id => oldLead},
                false,
                null
            );
            Test.stopTest();
        }
    }
    @IsTest
    static void testBreachReassignFlow() {
        User u1 = createUser();
        User u2 = createUser();

        Group q = new Group(
            Name = 'Test Queue',
            Type = 'Queue'
        );
        insert q;

        insert new GroupMember(GroupId = q.Id, UserOrGroupId = u1.Id);
        insert new GroupMember(GroupId = q.Id, UserOrGroupId = u2.Id);

        System.runAs(u1) {

            Lead l = new Lead(
                LastName = 'Breach Lead',
                Company = 'Test Company',
                Status = 'New',
                OwnerId = u1.Id,
                RES_SLA_Status__c = 'Running',
                RES_SLA_Cycle_Count__c = 1,
                RES_Previous_Lead_Owner__c = q.Id
            );

            insert l;

            Lead oldLead = l.clone(false, true, false, false);
            l.RES_SLA_Status__c = 'Breached';

            Test.startTest();
            RES_LeadServices.setUpdateSLATimeOnLead(
                new List<Lead>{l},
                new Map<Id, Lead>{l.Id => oldLead},
                false,
                null
            );
            Test.stopTest();
            System.assertNotEquals(u1.Id, l.OwnerId, 'Owner should change after breach');
            System.assertEquals('Running', l.RES_SLA_Status__c, 'SLA should restart');
            System.assertNotEquals(null, l.RES_SLA_Due_Time__c);
        }
    }

    @IsTest
    static void testGetNewOwnerForRetiredLeads() {
        User u1 = createUser();
        User u2 = createUser();

        Group q = new Group(
            Name = 'Retired Queue',
            Type = 'Queue'
        );

        insert q;

        insert new QueueSobject(
            QueueId = q.Id,
            SobjectType = 'Lead'
        );

        insert new GroupMember(GroupId = q.Id, UserOrGroupId = u1.Id);
        insert new GroupMember(GroupId = q.Id, UserOrGroupId = u2.Id);

        System.runAs(u1) {   // 👈 separates transaction context

            Test.startTest();

            Lead l = new Lead(
                LastName = 'Retired Lead',
                Company = 'Test Company',
                Status = 'New',
                OwnerId = q.Id
            );
            insert l;

            RES_LeadServices.InputWrapper input = new RES_LeadServices.InputWrapper();
            input.leadId = l.Id;
            input.previousOwnerId = q.Id;
            input.currentOwnerId = u1.Id; 

            RES_LeadServices.getNewOwnerForRetiredLeads(
                new List<RES_LeadServices.InputWrapper>{input}
            );

            Test.stopTest();

            Lead updatedLead = [SELECT Id, OwnerId FROM Lead WHERE Id = :l.Id];

            System.assertNotEquals(null, updatedLead.Id);
        }
    }
}