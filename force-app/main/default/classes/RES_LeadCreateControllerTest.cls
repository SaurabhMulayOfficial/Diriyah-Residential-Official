@isTest
private class RES_LeadCreateControllerTest {

    @testSetup
    static void setupData() {
        UserRole roleRecord = new UserRole(
            Name = 'Test Role',
            DeveloperName = 'Test_Role_For_Lead_Create'
        );
        insert roleRecord;

        Profile profileRecord = [
            SELECT Id
            FROM Profile
            WHERE Name = :System.Label.RES_Admin_Profile
            LIMIT 1
        ];

        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@example.com',
            Username = 'testuser' + System.currentTimeMillis() + '@example.com',
            Alias = 'tuser',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileRecord.Id,
            UserRoleId = roleRecord.Id
        );
        insert testUser;
    }

    @isTest
    static void testGetLeadRecordTypes() {
        Test.startTest();
        List<Map<String, String>> result = RES_LeadCreateController.getLeadRecordTypes();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Record type result should not be null.');
    }

    @isTest
    static void testGetRecordTypeById() {
        RecordType leadRecordType = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead'
            AND IsActive = true
            LIMIT 1
        ];

        Test.startTest();
        Map<String, String> result = RES_LeadCreateController.getRecordTypeById(leadRecordType.Id);
        Test.stopTest();

        System.assertEquals(leadRecordType.Id, result.get('id'));
    }

    @isTest
    static void testGetRecordTypeByBlankId() {
        Test.startTest();
        Map<String, String> result = RES_LeadCreateController.getRecordTypeById('');
        Test.stopTest();

        System.assertEquals(true, result.isEmpty());
    }

    @isTest
    static void testGetPicklistValues() {
        Test.startTest();
        List<Map<String, String>> result = RES_LeadCreateController.getPicklistValues('LeadSource');
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testGetPicklistValuesInvalidField() {
        Test.startTest();
        List<Map<String, String>> result = RES_LeadCreateController.getPicklistValues('Invalid_Field__c');
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    @isTest
    static void testGetCurrentUserRoleName() {
        Test.startTest();
        String roleName = RES_LeadCreateController.getCurrentUserRoleName();
        Test.stopTest();
 
        System.assert(
            roleName == null || String.isNotBlank(roleName),
            'Method should safely return either null or a valid role name.'
        );
    }

    @isTest
    static void testIsSystemAdmin() {
        Test.startTest();
        Boolean result = RES_LeadCreateController.isSystemAdmin();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Method should return true or false.');
    }

    @isTest
    static void testHasLeadSourceAccessByRoleFalse() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Alias = 'tuser'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Test.startTest();
            Boolean result = RES_LeadCreateController.hasLeadSourceAccessByRole();
            Test.stopTest();

            System.assertEquals(false, result);
        }
    }

    @isTest
    static void testCreateLead() {
        RecordType leadRecordType = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead'
            AND IsActive = true
            LIMIT 1
        ];

        Map<String, Object> fieldValues = new Map<String, Object>{
            'FirstName' => 'John',
            'LastName' => 'Doe',
            'Company' => 'Test Company',
            'MobilePhone' => '+1234567890'
        };

        Test.startTest();
        Lead createdLead = RES_LeadCreateController.createLead(fieldValues, leadRecordType.Id);
        Test.stopTest();

        System.assertNotEquals(null, createdLead.Id);
        System.assertEquals('John', createdLead.FirstName);
        System.assertEquals('Doe', createdLead.LastName);
    }

    @isTest
    static void testGetFilteredLeadSourceValues() {
        Test.startTest();
        List<Map<String, String>> result = RES_LeadCreateController.getFilteredLeadSourceValues();
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testGetFilteredIdentificationTypeValues() {
        Test.startTest();
        List<Map<String, String>> result = RES_LeadCreateController.getFilteredIdentificationTypeValues();
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testGetCityscapeYearValues() {
        Test.startTest();
        List<Map<String, String>> result = RES_LeadCreateController.getCityscapeYearValues();
        Test.stopTest();

        System.assertNotEquals(null, result);
    }
}