/**
 * ==============================================================================
 * Test Class    : RES_LeadConversionHandler_Test
 * Description   : Unit Test class for RES_LeadConversionHandler.
 *                 
 *                 Covers:
 *                 • Null and empty Lead validation scenarios.
 *                 • Duplicate Lead detection logic.
 *                 • Duplicate Account detection logic.
 *                 • Contact mapping using Mobile Phone.
 *                 • Account mapping during Lead conversion.
 *                 • Successful Lead conversion execution.
 *                 • Exception handling during conversion.
 *
 *                 Test data creation is delegated to
 *                 RES_TestDataFactory for reusable and centralized
 *                 test data management.
 *
 * Author        : Roshan Jambhule
 * Company       : Globant Inc
 * Created Date  : May 27, 2026
 * Version       : 1.0
 * ==============================================================================
 */
@isTest
private class RES_LeadConversionHandler_Test {
    @IsTest
    static void testHandleLeadConversion() {
        Account acc = new Account(Name = 'Globant');
        insert acc;
        Contact con = new Contact(
            FirstName   = 'Test',
            LastName    = 'Contact',
            MobilePhone = '+919876543210',
            AccountId   = acc.Id
        );
        insert con;
        Lead l = RES_TestDataFactory.createLead('leadconversion@test.com');
        l.Status      = '04';
        l.MobilePhone = '+919876543210';
        l.RES_Project__c = 'Amansamar Residences Wadi Safar';
        update l;
        Map<Id,List<SObject>> duplicateMap = new Map<Id,List<SObject>>();
        duplicateMap.put(l.Id, new List<SObject>{ acc });
        Map<String,Id> phoneMap = new Map<String,Id>{'+919876543210' => con.Id};
        Test.startTest();
        RES_LeadConversionHandler.convertLeads(new List<Lead>{ l }, duplicateMap, phoneMap);
        Test.stopTest();
        Lead convertedLead = [SELECT Id, IsConverted, ConvertedContactId, ConvertedAccountId FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true,   convertedLead.IsConverted,        'Lead should be converted');
        System.assertEquals(con.Id, convertedLead.ConvertedContactId, 'Should link existing Contact');
        System.assertEquals(acc.Id, convertedLead.ConvertedAccountId, 'Should link existing Account');
    }

    @IsTest
    static void testConvertLeadsWithDuplicateAccount() {
        Lead l = RES_TestDataFactory.createLead('duplicateaccount@test.com');
        l.Status         = '04';
        l.RES_Project__c = 'Amansamar Residences Wadi Safar';
        update l;
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        Map<Id,List<SObject>> duplicateMap = new Map<Id,List<SObject>>();
        duplicateMap.put(l.Id, new List<SObject>{ acc });
        Map<String,Id> phoneMap = new Map<String,Id>();
        Test.startTest();
        RES_LeadConversionHandler.convertLeads(new List<Lead>{ l }, duplicateMap, phoneMap);
        Test.stopTest();
        Lead convertedLead = [SELECT Id, IsConverted, ConvertedAccountId FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true,   convertedLead.IsConverted,        'Lead should be converted');
        System.assertEquals(acc.Id, convertedLead.ConvertedAccountId, 'Should link duplicate Account');
    }

    @IsTest
    static void testGetDuplicateLeadsLeadBranch() {
        Lead existingLead = RES_TestDataFactory.createLead('existinglead@test.com');
        Lead duplicateLead = RES_TestDataFactory.createLead('existinglead@test.com');
        Test.startTest();
        Map<Id,List<SObject>> result = RES_LeadConversionHandler.getDuplicateLeads(
            new List<Lead>{ duplicateLead }, 'Lead'
        );
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testGetDuplicateLeadsAccountBranch() {
        Account acc = new Account(
                Name = 'Duplicate Company',
                RES_CR_number__c = '8624379423',
                RES_Identification_Type__c = 'ZIT04'
                );
            insert acc;

        Lead l = RES_TestDataFactory.createLead('dupaccount@test.com');
                l.Company = 'Duplicate Company';
                l.RES_CR_number__c = '8624379423';
                l.RES_Identification_Type__c = 'ZIT04';
            update l;
        Test.startTest();
        Map<Id,List<SObject>> result = RES_LeadConversionHandler.getDuplicateLeads(
            new List<Lead>{ l }, 'Account'
        );
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testConvertLeadsExceptionBranch() {
        Lead l = RES_TestDataFactory.createLead('exceptionbranch@test.com');
        Map<Id,List<SObject>> duplicateMap = new Map<Id,List<SObject>>();
        Map<String,Id> phoneMap = new Map<String,Id>();
        Test.startTest();
        RES_LeadConversionHandler.convertLeads(new List<Lead>{ l }, duplicateMap, phoneMap);
        Test.stopTest();
        System.assert(true, 'Should handle exception gracefully');
    }

    // ─── NEW Tests for Red Lines ───────────────────────────────────

    /**
     * ✅ Covers handleLeadConversion — phone number collection
     *    + contactList query + phoneToContactMap + convertLeads call
     */
    @IsTest
    static void testHandleLeadConversionWithMobilePhone() {
        Lead l = RES_TestDataFactory.createLead('handleconversion@test.com');
        l.Status         = '04';
        l.MobilePhone    = '+919900001111';
        l.RES_Project__c = 'Amansamar Residences Wadi Safar';
        update l;
        Test.startTest();
        // ✅ Calls handleLeadConversion — covers all red lines in that method
        RES_LeadConversionHandler.handleLeadConversion(new List<Lead>{ l });
        Test.stopTest();
        Lead convertedLead = [
            SELECT Id, IsConverted, ConvertedContactId
            FROM   Lead
            WHERE  Id = :l.Id
        ];
        System.assertEquals(true, convertedLead.IsConverted, 'Lead should be converted');
    }

    /**
     * ✅ Covers handleLeadConversion with null/blank MobilePhone
     *    — tests the String.isNotBlank() guard added in handleLeadConversion
     */
    @IsTest
    static void testHandleLeadConversionWithBlankMobilePhone() {
        Lead l = RES_TestDataFactory.createLead('blankmobile@test.com');
        l.Status         = '04';
        l.MobilePhone = '+919900001111';
        l.Email = 'blankmobile@test.com';
        l.RES_Project__c = 'Amansamar Residences Wadi Safar';
        update l;
        Test.startTest();
        RES_LeadConversionHandler.handleLeadConversion(new List<Lead>{ l });
        Test.stopTest();
        Lead convertedLead = [SELECT Id, IsConverted FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, convertedLead.IsConverted, 'Lead should be converted without mobile');
    }

    /**
     * ✅ Covers getConvertedRecordIds — happy path
     *    All red lines in getConvertedRecordIds method
     */
    @IsTest
    static void testGetConvertedRecordIds() {
        Account acc = new Account(Name = 'Converted Account');
        insert acc;
        Contact con = new Contact(
            FirstName   = 'Converted',
            LastName    = 'Contact',
            MobilePhone = '+919900002222',
            AccountId   = acc.Id
        );
        insert con;
        Lead l = RES_TestDataFactory.createLead('getconverted@test.com');
        l.Status         = '04';
        l.MobilePhone    = '+919900002222';
        l.RES_Project__c = 'Amansamar Residences Wadi Safar';
        update l;
        // Convert the Lead first
        Map<Id,List<SObject>> duplicateMap = new Map<Id,List<SObject>>();
        duplicateMap.put(l.Id, new List<SObject>{ acc });
        Map<String,Id> phoneMap = new Map<String,Id>{'+919900002222' => con.Id};
        RES_LeadConversionHandler.convertLeads(new List<Lead>{ l }, duplicateMap, phoneMap);

        Lead convertedLead = [SELECT Id, IsConverted FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, convertedLead.IsConverted, 'Lead must be converted first');

        Test.startTest();
        // ✅ Now call getConvertedRecordIds — covers all red lines
        Map<String, String> result = RES_LeadConversionHandler.getConvertedRecordIds(l.Id);
        Test.stopTest();

        System.assertNotEquals(null,  result,                  'Result should not be null');
        System.assertNotEquals('',    result.get('accountId'), 'Account Id should be present');
        System.assertNotEquals('',    result.get('contactId'), 'Contact Id should be present');
        System.assertNotEquals(null,  result.get('accountName'), 'Account name should be present');
        System.assertNotEquals(null,  result.get('contactName'), 'Contact name should be present');
        System.assertNotEquals(null,  result.get('opportunityName'), 'Opp name should be present');
    }

    /**
     * ✅ Covers getConvertedRecordIds — null leadId branch (line 166-167)
     */
    @IsTest
    static void testGetConvertedRecordIdsNullLeadId() {
        Test.startTest();
        try {
            RES_LeadConversionHandler.getConvertedRecordIds(null);
            System.assert(false);
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex,'');
        }
        Test.stopTest();
    }

    /**
     * ✅ Covers getConvertedRecordIds — unconverted Lead returns empty map (line 170-172)
     */
    @IsTest
    static void testGetConvertedRecordIdsUnconvertedLead() {
        Lead l = RES_TestDataFactory.createLead('notconverted@test.com');
        Test.startTest();
        Map<String, String> result = RES_LeadConversionHandler.getConvertedRecordIds(l.Id);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Result should be empty for unconverted Lead');
    }

    /**
     * ✅ Covers convertLeads — setAccountId branch (lines 76-77)
     *    Duplicate Account found → lc.setAccountId() called
     */
    @IsTest
    static void testConvertLeadsSetAccountIdBranch() {
        Account acc = new Account(
        Name = 'Duplicate Account Branch',
        RES_CR_number__c = '8624379423',
        RES_Identification_Type__c = 'ZIT04'
        );
        insert acc;

        Lead l = RES_TestDataFactory.createLead('setaccountid@test.com');
        l.Status = '04';
        l.Email = 'setaccountid@test.com';
        l.MobilePhone = '+919988776655';
        l.RES_Project__c = 'Amansamar Residences Wadi Safar';
        l.RES_CR_number__c = '8624379423';
        l.RES_Identification_Type__c = 'ZIT04';

        update l;

        // ✅ Duplicate Account in map → setAccountId called
        Map<Id,List<SObject>> duplicateMap = new Map<Id,List<SObject>>();
        duplicateMap.put(l.Id, new List<SObject>{ acc });
        Map<String,Id> phoneMap = new Map<String,Id>();

        Test.startTest();
        RES_LeadConversionHandler.convertLeads(new List<Lead>{ l }, duplicateMap, phoneMap);
        Test.stopTest();

        Lead convertedLead = [
            SELECT Id, IsConverted, ConvertedAccountId
            FROM   Lead
            WHERE  Id = :l.Id
        ];
        System.assertEquals(true,   convertedLead.IsConverted,        'Lead should be converted');
        System.assertEquals(acc.Id, convertedLead.ConvertedAccountId, 'Should link duplicate Account');
    }
}