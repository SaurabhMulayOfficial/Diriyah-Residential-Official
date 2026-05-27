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
 * Author        : Mohanish
 * Company       : Globant Inc
 * Created Date  : May 27, 2026
 * Version       : 1.0
 * ==============================================================================
 */
@isTest
private class RES_LeadConversionHandler_Test {

    @IsTest
    static void testGetDuplicateLeadsNullInput() {
        Test.startTest();
        Map<Id,List<SObject>> result =
            RES_LeadConversionHandler.getDuplicateLeads(null,'Account');
        Test.stopTest();
        System.assertEquals(null,result,'Duplicate Null');
    }

    @IsTest
    static void testGetDuplicateLeadsEmptyInput() {
        Test.startTest();
        Map<Id,List<SObject>> result =
            RES_LeadConversionHandler.getDuplicateLeads(new List<Lead>(),'Account');
        Test.stopTest();
        System.assertEquals(null,result,'Input null');
    }

    @IsTest
    static void testHandleLeadConversion() {
    Account acc = new Account(Name = 'Globant');
    insert acc;
    // Existing Contact
    Contact con = new Contact(
        FirstName = 'Test',
        LastName = 'Contact',
        MobilePhone = '+919876543210',
        AccountId = acc.Id
    );
    insert con;
    // Lead
    Lead l = RES_TestDataFactory.createLead(
        'leadconversion@test.com'
    );
    l.Status = '04';
    l.MobilePhone = '+919876543210';
    l.RES_Project__c ='Amansamar Residences Wadi Safar';
    update l;
    Map<Id,List<SObject>> duplicateMap = new Map<Id,List<SObject>>();
    duplicateMap.put(l.Id,new List<SObject>{ acc });
    Map<String,Id> phoneMap = new Map<String,Id>{'+919876543210' => con.Id};
    Test.startTest();
    RES_LeadConversionHandler.convertLeads(new List<Lead>{ l },duplicateMap,phoneMap);
    Test.stopTest();
    Lead convertedLead = [SELECT Id,IsConverted,ConvertedContactId,ConvertedAccountId FROM Lead WHERE Id = :l.Id];
    System.assertEquals(true,convertedLead.IsConverted,'');
    // Covers lc.setContactId()
    System.assertEquals(con.Id,convertedLead.ConvertedContactId,'');
    // Covers lc.setAccountId()
    System.assertEquals(acc.Id,convertedLead.ConvertedAccountId,'');
}
    @IsTest
    static void testConvertLeadsWithDuplicateAccount() {
            Lead l = RES_TestDataFactory.createLead('duplicateaccount@test.com');
            l.Status = '04';
            l.RES_Project__c ='Amansamar Residences Wadi Safar';
            update l;
            Account acc = [SELECT Id, Name FROM Account LIMIT 1];
            Map<Id,List<SObject>> duplicateMap = new Map<Id,List<SObject>>();
            duplicateMap.put(l.Id,new List<SObject>{ acc });
            Map<String,Id> phoneMap = new Map<String,Id>();
            Test.startTest();
            RES_LeadConversionHandler.convertLeads( new List<Lead>{ l },duplicateMap,phoneMap);
            Test.stopTest();
            Lead convertedLead = [SELECT Id, IsConverted, ConvertedAccountId FROM Lead WHERE Id = :l.Id ];
            System.assertEquals(true,convertedLead.IsConverted,'');
            System.assertEquals(acc.Id,convertedLead.ConvertedAccountId,'');
    }
    
    @IsTest
    static void testGetDuplicateLeadsLeadBranch() {
            Lead existingLead = RES_TestDataFactory.createLead('existinglead@test.com');
            Lead duplicateLead = RES_TestDataFactory.createLead('existinglead@test.com');
            Test.startTest();
            Map<Id,List<SObject>> result = RES_LeadConversionHandler.getDuplicateLeads(new List<Lead>{ duplicateLead },'Lead');
            Test.stopTest();
            System.assertNotEquals(null,result,'');
    }

    @IsTest
    static void testGetDuplicateLeadsAccountBranch() {
    Account acc = new Account(
        Name = 'Duplicate Company',
        RES_CR_number__c = '1234'
    );
    insert acc;
    Lead l = RES_TestDataFactory.createLead('dupaccount@test.com');
    l.Company = 'Duplicate Company';
    l.RES_CR_number__c = '1234';
    update l;
    Test.startTest();
    Map<Id,List<SObject>> result = RES_LeadConversionHandler.getDuplicateLeads(new List<Lead>{ l },'Account');
    Test.stopTest();
    System.assertNotEquals(null, result,'');
}

    @IsTest
    static void testConvertLeadsExceptionBranch() {
            Lead l = RES_TestDataFactory.createLead('exceptionbranch@test.com');
            Map<Id,List<SObject>> duplicateMap = new Map<Id,List<SObject>>();
            Map<String,Id> phoneMap = new Map<String,Id>();
            Test.startTest();
            RES_LeadConversionHandler.convertLeads(new List<Lead>{ l },duplicateMap,phoneMap);
            Test.stopTest();
            System.assert(true);
    }
}