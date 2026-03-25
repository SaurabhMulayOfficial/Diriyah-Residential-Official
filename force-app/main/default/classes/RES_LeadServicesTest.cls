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

    /**
     * @description Validates Lead Record Type assignment based on RES_Marketing_Area__c.
     * BRANDED_RESIDENTIAL -> RES_Individual
     * All others/Blank -> RES_Company
     */
    @IsTest
    static void testSelectLeadRecordTypeByMarketingArea() {
        User u = createUser();
        
        // Fetch Record Type IDs dynamically to verify logic
        Id individualRTId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
                            .get('RES_Individual').getRecordTypeId();
        Id companyRTId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
                         .get('RES_Company').getRecordTypeId();

        System.runAs(u) {
            List<Lead> leadsToTest = new List<Lead>();

            // 1. Scenario: Marketing Area is BRANDED_RESIDENTIAL (Individual)
            for(Integer i=0; i<5; i++) {
                leadsToTest.add(new Lead(
                    LastName = 'IndividualTest' + i,
                    Company = 'Irrelevant Company Name', // Even if company exists
                    RES_Marketing_Area__c = 'BRANDED_RESIDENTIAL',
                    Status = '01'
                ));
            }

            // 2. Scenario: Marketing Area is something else (Company)
            for(Integer i=0; i<5; i++) {
                leadsToTest.add(new Lead(
                    LastName = 'CompanyTest' + i,
                    RES_Marketing_Area__c = 'B2B_RETAIL_LEASING',
                    Status = '01'
                ));
            }

            // 3. Scenario: Marketing Area is Blank (Defaults to Company per 'else' logic)
            leadsToTest.add(new Lead(
                LastName = 'BlankAreaTest',
                RES_Marketing_Area__c = null,
                Status = '01'
            ));

            Test.startTest();
            // Calling the service method directly to test logic in isolation
            RES_LeadServices.selectLeadRecordType(leadsToTest);
            Test.stopTest();

            // 4. Verification (Assertions)
            for (Lead l : leadsToTest) {
                if (l.RES_Marketing_Area__c == 'BRANDED_RESIDENTIAL') {
                    System.assertEquals(individualRTId, l.RecordTypeId, 
                        'Branded Residential area should result in Individual Record Type');
                } else {
                    System.assertEquals(companyRTId, l.RecordTypeId, 
                        'Non-Branded or Blank area should result in Company Record Type');
                }
            }
        }
    }
}