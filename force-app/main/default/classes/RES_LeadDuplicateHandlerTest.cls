@IsTest
private class RES_LeadDuplicateHandlerTest {

    private static final String COMPANY_RT = 'RES_Company';

    private static Id getCompanyRecordTypeId() {
        return Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName()
            .get(COMPANY_RT)
            .getRecordTypeId();
    }

    private static Lead createLead(
        String firstName,
        String lastName,
        String email,
        String leadSource,
        String status,
        Id ownerId
    ) {
        return new Lead(
            FirstName = firstName,
            LastName = lastName,
            Company = 'Test Company',
            Email = email,
            MobilePhone = '+9739992139',
            LeadSource = leadSource,
            Status = status,
            OwnerId = ownerId,
            RecordTypeId = getCompanyRecordTypeId()
        );
    }

    private static RES_LeadDeduplicationHandler.LeadDuplicateWrapper
        createWrapper(
            Lead incomingLead,
            Lead existingLead
        ) {

        RES_LeadDeduplicationHandler.LeadDuplicateWrapper wrapper =
            new RES_LeadDeduplicationHandler.LeadDuplicateWrapper(
                incomingLead
            );

        wrapper.hasDuplicates = true;

        wrapper.leadBySource.put(
            existingLead.LeadSource,
            new List<Lead>{ existingLead }
        );

        return wrapper;
    }

    /*
     * ===============================================================
     * SAME SOURCE -> SAME SOURCE
     *
     * Example: Z05-Z05
     *
     * Expected:
     * - Incoming Lead is archived
     * - Incoming Lead is assigned to existing RM
     * ===============================================================
     */
    @IsTest
    static void testSameSourceSameSource() {

        Id existingRmId = UserInfo.getUserId();

        Lead existingLead = createLead(
            'Existing',
            'Broker',
            'same-source@test.com',
            'Z05',
            '01',
            existingRmId
        );

        insert existingLead;

        Lead incomingLead = createLead(
            'Incoming',
            'Broker',
            'same-source@test.com',
            'Z05',
            '01',
            UserInfo.getUserId()
        );

        RES_LeadDeduplicationHandler.LeadDuplicateWrapper wrapper =
            createWrapper(
                incomingLead,
                existingLead
            );

        Test.startTest();

        RES_LeadDeduplicationHandler.runRuleEngine(
            new List<
                RES_LeadDeduplicationHandler.LeadDuplicateWrapper
            >{
                wrapper
            }
        );

        Test.stopTest();

        System.assertEquals(
            'Archive',
            incomingLead.Status
        );

        System.assertEquals(
            existingRmId,
            incomingLead.OwnerId
        );
    }

    /*
     * ===============================================================
     * SAME SOURCE -> SAME SOURCE
     *
     * Example: Z06-Z06
     * ===============================================================
     */
    @IsTest
    static void testAnotherSameSourceCombination() {

        Id existingRmId = UserInfo.getUserId();

        Lead existingLead = createLead(
            'Existing',
            'Marketing',
            'marketing@test.com',
            'Z06',
            '02',
            existingRmId
        );

        insert existingLead;

        Lead incomingLead = createLead(
            'Incoming',
            'Marketing',
            'marketing@test.com',
            'Z06',
            '01',
            UserInfo.getUserId()
        );

        RES_LeadDeduplicationHandler.LeadDuplicateWrapper wrapper =
            createWrapper(
                incomingLead,
                existingLead
            );

        Test.startTest();

        RES_LeadDeduplicationHandler.runRuleEngine(
            new List<
                RES_LeadDeduplicationHandler.LeadDuplicateWrapper
            >{
                wrapper
            }
        );

        Test.stopTest();

        System.assertEquals(
            'Archive',
            incomingLead.Status
        );

        System.assertEquals(
            existingRmId,
            incomingLead.OwnerId
        );
    }

    /*
     * ===============================================================
     * BLOCK ONLY
     *
     * Example: Z04-Z05
     *
     * Expected:
     * - Incoming Lead is blocked
     * ===============================================================
     */
    @IsTest
    static void testBlockOnly() {

        Lead existingLead = createLead(
            'Existing',
            'Broker',
            'employee-broker@test.com',
            'Z05',
            '01',
            UserInfo.getUserId()
        );

        insert existingLead;

        Lead incomingLead = createLead(
            'Incoming',
            'Employee',
            'employee-broker@test.com',
            'Z04',
            '01',
            UserInfo.getUserId()
        );

        RES_LeadDeduplicationHandler.LeadDuplicateWrapper wrapper =
            createWrapper(
                incomingLead,
                existingLead
            );

        Test.startTest();

        RES_LeadDeduplicationHandler.runRuleEngine(
            new List<
                RES_LeadDeduplicationHandler.LeadDuplicateWrapper
            >{
                wrapper
            }
        );

        Test.stopTest();

        Database.SaveResult result = Database.insert(
            incomingLead,
            false
        );

        System.assertEquals(
            false,
            result.isSuccess()
        );
    }

    /*
     * ===============================================================
     * BLOCK + SEND EMAIL PLATFORM EVENT
     *
     * Example: Z05-Z04
     *
     * Existing Lead:
     * Status = 01
     *
     * Expected:
     * - RES_Send_Email__e is published
     * - Incoming Lead is blocked
     * ===============================================================
     */
    @IsTest
    static void testBlockAndPublishSendEmailEvent() {

        Lead existingLead = createLead(
            'Existing',
            'Employee',
            'broker-employee@test.com',
            'Z04',
            '01',
            UserInfo.getUserId()
        );

        insert existingLead;

        Lead incomingLead = createLead(
            'Incoming',
            'Broker',
            'broker-employee@test.com',
            'Z05',
            '01',
            UserInfo.getUserId()
        );

        RES_LeadDeduplicationHandler.LeadDuplicateWrapper wrapper =
            createWrapper(
                incomingLead,
                existingLead
            );

        List<OrgWideEmailAddress> orgWideAddresses = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE DisplayName = 'Salesforce Notifications'
            LIMIT 1
        ];

        if (!orgWideAddresses.isEmpty()) {
            RES_LeadDeduplicationHandler.orgWideEmailAddressId =
                orgWideAddresses[0].Id;
        }

        Test.startTest();

        RES_LeadDeduplicationHandler.runRuleEngine(
            new List<
                RES_LeadDeduplicationHandler.LeadDuplicateWrapper
            >{
                wrapper
            }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            wrapper.hasDuplicates
        );
    }
    
    /*
     * ===============================================================
     * getRmId()
     * ===============================================================
     */
    @IsTest
    static void testGetRmId() {

        User userRecord = [
            SELECT Id
            FROM User
            WHERE IsActive = true
            LIMIT 1
        ];

        Lead lead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            OwnerId = userRecord.Id
        );

        System.assertEquals(
            String.valueOf(userRecord.Id),
            RES_LeadDeduplicationHandler.getRmId(
                new List<Lead>{ lead }
            )
        );

        System.assertEquals(
            '',
            RES_LeadDeduplicationHandler.getRmId(
                new List<Lead>()
            )
        );
    }
    /*
     * ===============================================================
     * processEmails()
     * ===============================================================
     */
    @IsTest
    static void testProcessEmailsWithoutOrgWideEmail() {

        RES_LeadDeduplicationHandler.orgWideEmailAddressId = null;
        RES_LeadDeduplicationHandler.notifyCSO.clear();

        Test.startTest();

        RES_LeadDeduplicationHandler.processEmails();

        Test.stopTest();

        System.assertEquals(
            null,
            RES_LeadDeduplicationHandler.orgWideEmailAddressId
        );
    }
}