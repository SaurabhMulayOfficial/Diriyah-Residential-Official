@IsTest
private class RES_ConvertedLeadControllerTest {

    @TestSetup
    static void setupData() {
        Lead ld = new Lead(
            FirstName = 'Main',
            LastName = 'Test Lead',
            Company = 'Main Converted Leads Account',
            Email = 'mainlead@test.com',
            MobilePhone = '+966500000002',
            LeadSource = getLeadSourceValue(),
            Status = getOpenLeadStatus()
        );

        Id leadRtId = getLeadRecordTypeId('RES_Company');
        if (leadRtId != null) {
            ld.RecordTypeId = leadRtId;
        }

        insert ld;
    }

    @IsTest
    static void testAdminBranch() {
        Lead mockLead = getMockLead(UserInfo.getUserId());

        RES_ConvertedLeadService.testAdminProfileId = UserInfo.getProfileId();
        RES_ConvertedLeadService.testConvertedLeads = new List<Lead>{ mockLead };

        Test.startTest();
        RES_ConvertedLeadService.ConvertedLeadResponse response =
            RES_ConvertedLeadController.getConvertedLeads(1, 20, '');
        Test.stopTest();

        System.assertEquals('All Converted Leads', response.heading);
        System.assertEquals(1, response.leads.size());

        clearOverrides();
    }

    @IsTest
    static void testMyConvertedLeadsBranch() {
        UserRole roleRecord = createUserRole('MyConvertedRole');
        User testUser = createTestUser('myuser', roleRecord.Id, null);

        Lead mockLead = getMockLead(testUser.Id);

        RES_ConvertedLeadService.testMyConvertedRoleIds =
            new Set<Id>{ roleRecord.Id };
        RES_ConvertedLeadService.testConvertedLeads =
            new List<Lead>{ mockLead };

        System.runAs(testUser) {
            Test.startTest();
            RES_ConvertedLeadService.ConvertedLeadResponse response =
                RES_ConvertedLeadController.getConvertedLeads(1, 20, '');
            Test.stopTest();

            System.assertEquals('My Converted Leads', response.heading);
            System.assertEquals(1, response.leads.size());
            System.assertEquals('Main Test Lead', response.leads[0].name);
        }

        clearOverrides();
    }

    @IsTest
    static void testMyTeamConvertedLeadsBranch() {
        UserRole managerRole = createUserRole('ManagerRole');
        UserRole childRole = createUserRole('ChildRole');

        User managerUser = createTestUser('manageruser', managerRole.Id, null);
        User childUser = createTestUser('childuser', childRole.Id, managerUser.Id);

        Lead mockLead = getMockLead(childUser.Id);

        RES_ConvertedLeadService.testMyTeamConvertedRoleIds =
            new Set<Id>{ managerRole.Id };
        RES_ConvertedLeadService.testConvertedLeads =
            new List<Lead>{ mockLead };

        System.runAs(managerUser) {
            Test.startTest();
            RES_ConvertedLeadService.ConvertedLeadResponse response =
                RES_ConvertedLeadController.getConvertedLeads(1, 20, '');
            Test.stopTest();

            System.assertEquals('My Team Converted Leads', response.heading);
            System.assertEquals(1, response.leads.size());
        }

        clearOverrides();
    }

    @IsTest
    static void testNoRoleMatchBranch() {
        User testUser = createTestUser('noroleuser', null, null);

        RES_ConvertedLeadService.testConvertedLeads =
            new List<Lead>{ getMockLead(UserInfo.getUserId()) };

        System.runAs(testUser) {
            Test.startTest();
            RES_ConvertedLeadService.ConvertedLeadResponse response =
                RES_ConvertedLeadController.getConvertedLeads(1, 20, '');
            Test.stopTest();

            System.assertEquals('Converted Leads', response.heading);
            System.assertEquals(0, response.leads.size());
        }

        clearOverrides();
    }

    @IsTest
    static void testDaoGetConvertedLeads() {
        Test.startTest();
        List<Lead> convertedLeads =
            new RES_LeadDAOLayer().getConvertedLeads();
        Test.stopTest();

        System.assertNotEquals(null, convertedLeads);
    }

    @IsTest
    static void testDaoGetConvertedLeadByIdForNonConvertedLead() {
        Lead testLead = [
            SELECT Id
            FROM Lead
            WHERE Email = 'mainlead@test.com'
            LIMIT 1
        ];

        Test.startTest();
        Lead result =
            new RES_LeadDAOLayer().getConvertedLeadById(testLead.Id);
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void testDaoGetConvertedLeadByNullId() {
        Test.startTest();
        Lead result =
            new RES_LeadDAOLayer().getConvertedLeadById(null);
        Test.stopTest();

        System.assertEquals(null, result);
    }

    private static Lead getMockLead(Id ownerId) {
        Lead ld = [
            SELECT Id, Name, OwnerId, Owner.Name, Status, Company, Email,
                   MobilePhone, LeadSource, CreatedDate, ConvertedDate
            FROM Lead
            WHERE Email = 'mainlead@test.com'
            LIMIT 1
        ];

        ld.OwnerId = ownerId;
        return ld;
    }

    private static void clearOverrides() {
        RES_ConvertedLeadService.testAdminProfileId = null;
        RES_ConvertedLeadService.testMyConvertedRoleIds = null;
        RES_ConvertedLeadService.testMyTeamConvertedRoleIds = null;
        RES_ConvertedLeadService.testConvertedLeads = null;
    }

    private static UserRole createUserRole(String namePrefix) {
        UserRole roleRecord = new UserRole(
            Name = namePrefix + System.currentTimeMillis(),
            DeveloperName = namePrefix + System.currentTimeMillis()
        );
        insert roleRecord;
        return roleRecord;
    }

    private static User createTestUser(
        String aliasPrefix,
        Id roleId,
        Id managerId
    ) {
        Profile profileRecord = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        Long uniqueValue = System.currentTimeMillis();

        User usr = new User(
            FirstName = aliasPrefix,
            LastName = 'Tester',
            Alias = aliasPrefix.left(8),
            Email = aliasPrefix + uniqueValue + '@test.com',
            Username = aliasPrefix + uniqueValue + '@test.com',
            CommunityNickname = aliasPrefix + uniqueValue,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileRecord.Id
        );

        if (roleId != null) {
            usr.UserRoleId = roleId;
        }

        if (managerId != null) {
            usr.ManagerId = managerId;
        }

        insert usr;
        return usr;
    }

    private static String getOpenLeadStatus() {
        LeadStatus statusRecord = [
            SELECT MasterLabel, ApiName
            FROM LeadStatus
            WHERE IsConverted = false
            ORDER BY SortOrder ASC
            LIMIT 1
        ];

        return String.isNotBlank(statusRecord.ApiName)
            ? statusRecord.ApiName
            : statusRecord.MasterLabel;
    }

    private static String getLeadSourceValue() {
        for (Schema.PicklistEntry entry : Lead.LeadSource.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }

    private static Id getLeadRecordTypeId(String developerName) {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead'
            AND DeveloperName = :developerName
            LIMIT 1
        ];

        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }
}