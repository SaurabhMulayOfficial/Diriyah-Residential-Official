@IsTest

private class RES_AccountConvertedLeadControllerTest {
    private static Id businessAccountId;
    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'Converted Lead Account'
        );
        insert acc;
        businessAccountId = acc.Id;
        Lead ld = new Lead(
            FirstName = 'Converted',
            LastName = 'Lead',
            Company = 'Converted Lead Account',
            Email = 'convertedlead@test.com',
            MobilePhone = '+966500000001',
            Rating = 'Hot',
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
    static void testGetConvertedLeadsByAccountId() {
        Account acc = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];
        Test.startTest();
        RES_AccountConvertedLeadService.ConvertedLeadResponse response =
            RES_AccountConvertedLeadController.getConvertedLeadsByAccountId(acc.Id);
        Test.stopTest();
        System.assertNotEquals(
            null,
            response
        );
        System.assertNotEquals(
            null,
            response.leads
        );
        System.assert(
            response.totalCount >= 0
        );
    }

    @IsTest
    static void testGetAccountName() {
        Account acc = [
            SELECT Id,
                   Name
            FROM Account
            LIMIT 1
        ];
        Test.startTest();
        String accountName =
            RES_AccountConvertedLeadController.getAccountName(acc.Id);
        Test.stopTest();
        System.assertEquals(
            acc.Name,
            accountName
        );
    }

    @IsTest
    static void testNullAccountId() {
        Test.startTest();
        RES_AccountConvertedLeadService.ConvertedLeadResponse response =
            RES_AccountConvertedLeadController.getConvertedLeadsByAccountId(null);
        Test.stopTest();
        System.assertEquals(0, response.totalCount);
        System.assertEquals(false, response.isPersonAccount);
        System.assertEquals(0, response.leads.size());
    }

    @IsTest
    static void testGetAccountNameNull() {
        Test.startTest();
        String result =
            RES_AccountConvertedLeadController.getAccountName(null);
        Test.stopTest();
        System.assertEquals(
            '',
            result
        );
    }

    private static String getOpenLeadStatus() {
        LeadStatus statusRecord = [
            SELECT MasterLabel,
                   ApiName
            FROM LeadStatus
            WHERE IsConverted = false
            LIMIT 1
        ];
        return String.isNotBlank(statusRecord.ApiName)
            ? statusRecord.ApiName
            : statusRecord.MasterLabel;
    }

    private static String getLeadSourceValue() {
        for (
            Schema.PicklistEntry entry :
            Lead.LeadSource
                .getDescribe()
                .getPicklistValues()
        ) {

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
            WHERE SObjectType='Lead'
            AND DeveloperName=:developerName
            LIMIT 1
        ];

        return recordTypes.isEmpty()
            ? null
            : recordTypes[0].Id;
    }

    @IsTest
    static void testServiceGetConvertedLeadsByAccountIdDirectly() {
        Account acc = [
        SELECT Id
        FROM Account
        LIMIT 1
        ];

    Test.startTest();
        RES_AccountConvertedLeadService.ConvertedLeadResponse response =
        RES_AccountConvertedLeadService.getConvertedLeadsByAccountId(acc.Id);
    Test.stopTest();

    System.assertNotEquals(null, response);
    System.assertNotEquals(null, response.leads);
    System.assertEquals(false, response.isPersonAccount);
    System.assertEquals(response.leads.size(), response.totalCount);
    }

    @IsTest
    static void testServiceGetConvertedLeadsByNullAccountIdDirectly() {
    Test.startTest();
    RES_AccountConvertedLeadService.ConvertedLeadResponse response =
        RES_AccountConvertedLeadService.getConvertedLeadsByAccountId(null);
    Test.stopTest();
    System.assertNotEquals(null, response);
    System.assertEquals(0, response.totalCount);
    System.assertEquals(false, response.isPersonAccount);
    System.assertEquals(0, response.leads.size());
    }

    @IsTest
    static void testServiceGetAccountNameDirectly() {
    Account acc = [
        SELECT Id, Name
        FROM Account
        LIMIT 1
    ];

    Test.startTest();
    String accountName = RES_AccountConvertedLeadService.getAccountName(acc.Id);
    Test.stopTest();
    System.assertEquals(acc.Name, accountName);
    }

    @IsTest
    static void testServiceGetAccountNameWithNull() {
    Test.startTest();
    String accountName = RES_AccountConvertedLeadService.getAccountName(null);
    Test.stopTest();
    System.assertEquals('', accountName);
    }

    @IsTest
    static void testServiceForPersonAccountCoverage() {
    Id personRtId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('PersonAccount')
        .getRecordTypeId();
    Account pa = new Account(
        RecordTypeId = personRtId,
        FirstName = 'Test',
        LastName = 'Person',
        PersonMobilePhone ='+966500000999'
    );
    insert pa;
    Lead fakeLead = new Lead(
        LastName='Lead',
        Company='Temp',
        Email='person@test.com',
        MobilePhone='+966500000999',
        Rating='Hot'
    );
    RES_AccountConvertedLeadService.testConvertedLeads =
        new List<Lead>{ fakeLead };
    Test.startTest();
    RES_AccountConvertedLeadService.ConvertedLeadResponse response =
        RES_AccountConvertedLeadService.getConvertedLeadsByAccountId(pa.Id);
    Test.stopTest();
    System.assertEquals(true, response.isPersonAccount);
    System.assertEquals(1, response.totalCount);
    System.assertEquals('Hot', response.leads[0].ratingLabel);
    RES_AccountConvertedLeadService.testConvertedLeads = null;
    }

    @IsTest
    static void testServiceWithEmptyInjectedLeads() {
    Account acc = [
        SELECT Id
        FROM Account
        LIMIT 1
    ];
    RES_AccountConvertedLeadService.testConvertedLeads =
        new List<Lead>();
    Test.startTest();
    RES_AccountConvertedLeadService.ConvertedLeadResponse response =
        RES_AccountConvertedLeadService.getConvertedLeadsByAccountId(
            acc.Id
        );
    Test.stopTest();
    System.assertEquals(0, response.totalCount);
    System.assertEquals(0, response.leads.size());
    RES_AccountConvertedLeadService.testConvertedLeads = null;
    }
}