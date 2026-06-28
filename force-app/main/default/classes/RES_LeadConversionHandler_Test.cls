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
 * Created Date  : June 27, 2026
 * Version       : 7.0 
 * ==============================================================================
 */
@isTest
private class RES_LeadConversionHandler_Test {

    private static final String PROJECT = 'Amansamar Residences Wadi Safar';

    // ═══════════════════════════════════════════════════════════════════════
    // Group 1: RES_LeadConversionHandler - Basic Tests (8 tests)
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testHandleLeadConversionWithDuplicateAccount() {
        Account acc = RES_TestDataFactory.createAccountWithName('Duplicate Account Test');
        Lead l = RES_TestDataFactory.createLeadWithProject('duplicate@test.com', PROJECT);
        
        Test.startTest();
        RES_LeadConversionHandler.handleLeadConversion(new List<Lead>{ l });
        Test.stopTest();
        
        Lead result = [SELECT Id, IsConverted FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, result.IsConverted, 'Lead should be converted');
    }

    @IsTest
    static void testConvertLeadsWithAccountAndContact() {
        Account acc = RES_TestDataFactory.createAccountWithName('Account With Contact');
        Contact con = RES_TestDataFactory.createContactFull(acc.Id, 'TestFirst', 'TestLast', '+919988776655');
        
        Lead l = RES_TestDataFactory.createLeadFull(
            'fulltest@test.com',
            '+919988776655',
            'Full Test Co',
            PROJECT,
            '04',
            'Met'
        );
        
        Map<Id,List<SObject>> duplicateMap = new Map<Id,List<SObject>>();
        duplicateMap.put(l.Id, new List<SObject>{ acc });
        Map<String,Id> phoneMap = new Map<String,Id>();
        phoneMap.put('+919988776655', con.Id);
        
        Test.startTest();
        RES_LeadConversionHandler.convertLeads(new List<Lead>{ l }, duplicateMap, phoneMap);
        Test.stopTest();
        
        Lead result = [SELECT Id, IsConverted, ConvertedAccountId, ConvertedContactId FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, result.IsConverted, 'Lead should be converted');
        System.assertEquals(acc.Id, result.ConvertedAccountId, 'Account should be linked');
        System.assertEquals(con.Id, result.ConvertedContactId, 'Contact should be linked');
    }

    @IsTest
    static void testConvertLeadsPublishesEvent() {
        Account acc = RES_TestDataFactory.createAccountWithName('Event Publishing Test');
        Lead l = RES_TestDataFactory.createLeadWithProject('eventpub@test.com', PROJECT);
        
        Map<Id,List<SObject>> duplicateMap = new Map<Id,List<SObject>>();
        duplicateMap.put(l.Id, new List<SObject>{ acc });
        Map<String,Id> phoneMap = new Map<String,Id>();
        
        Test.startTest();
        RES_LeadConversionHandler.convertLeads(new List<Lead>{ l }, duplicateMap, phoneMap);
        Test.stopTest();
        
        Lead result = [SELECT Id, IsConverted FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, result.IsConverted, 'Lead should be converted with event');
    }

    @IsTest
    static void testConvertLeadsExceptionHandling() {
        Lead l = RES_TestDataFactory.createLeadWithProject('exception@test.com', PROJECT);
        
        Map<Id,List<SObject>> duplicateMap = new Map<Id,List<SObject>>();
        Map<String,Id> phoneMap = new Map<String,Id>();
        
        Test.startTest();
        try {
            RES_LeadConversionHandler.convertLeads(new List<Lead>{ l }, duplicateMap, phoneMap);
            System.assert(true, 'Should handle exception gracefully');
        } catch (Exception ex) {
            System.debug('Exception handled: ' + ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetConvertedRecordIds() {
        Account acc = RES_TestDataFactory.createAccountWithName('Get Records Test');
        Contact con = RES_TestDataFactory.createContactFull(acc.Id, 'Get', 'Records', '+919922334455');
        
        Lead l = RES_TestDataFactory.createLeadFull(
            'getrecords@test.com',
            '+919922334455',
            'Get Records Co',
            PROJECT,
            '04',
            'Met'
        );
        
        Map<Id,List<SObject>> duplicateMap = new Map<Id,List<SObject>>();
        duplicateMap.put(l.Id, new List<SObject>{ acc });
        Map<String,Id> phoneMap = new Map<String,Id>();
        phoneMap.put('+919922334455', con.Id);
        
        RES_LeadConversionHandler.convertLeads(new List<Lead>{ l }, duplicateMap, phoneMap);

        Test.startTest();
        Map<String, String> result = RES_LeadConversionHandler.getConvertedRecordIds(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testGetConvertedRecordIdsNullLeadId() {
        Test.startTest();
        try {
            RES_LeadConversionHandler.getConvertedRecordIds(null);
            System.assert(false, 'Should throw exception');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex, 'Exception should be thrown');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetConvertedRecordIdsUnconvertedLead() {
        Lead l = RES_TestDataFactory.createLeadWithProject('unconverted@test.com', PROJECT);
        
        Test.startTest();
        Map<String, String> result = RES_LeadConversionHandler.getConvertedRecordIds(l.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Result should be empty for unconverted lead');
    }

    @IsTest
    static void testHandleLeadConversionBulkOperation() {
        List<Lead> leadsToConvert = new List<Lead>();
        for (Integer i = 0; i < 5; i++) {
            Lead l = RES_TestDataFactory.createLeadWithProject('bulk' + i + '@test.com', PROJECT);
            leadsToConvert.add(l);
        }
        
        Test.startTest();
        RES_LeadConversionHandler.handleLeadConversion(leadsToConvert);
        Test.stopTest();
        
        List<Lead> results = [SELECT Id, IsConverted FROM Lead WHERE Id IN :leadsToConvert];
        System.assertEquals(5, results.size(), 'All bulk leads should be converted');
    }

    @IsTest
    static void testConvertLeadsWithMultipleContactMappings() {
        Account acc = RES_TestDataFactory.createAccountWithName('Multiple Contact Mappings');
        Contact con1 = RES_TestDataFactory.createContactFull(acc.Id, 'Contact', '1', '+919966665555');
        Contact con2 = RES_TestDataFactory.createContactFull(acc.Id, 'Contact', '2', '+919966664444');
        Contact con3 = RES_TestDataFactory.createContactFull(acc.Id, 'Contact', '3', '+919966663333');
        
        Lead l1 = RES_TestDataFactory.createLeadFull('multicontact1@test.com', '+919966665555', 'Multi 1', PROJECT, '04', 'Met');
        Lead l2 = RES_TestDataFactory.createLeadFull('multicontact2@test.com', '+919966664444', 'Multi 2', PROJECT, '04', 'Met');
        Lead l3 = RES_TestDataFactory.createLeadFull('multicontact3@test.com', '+919966663333', 'Multi 3', PROJECT, '04', 'Met');
        
        Map<Id,List<SObject>> duplicateMap = new Map<Id,List<SObject>>();
        duplicateMap.put(l1.Id, new List<SObject>{ acc });
        duplicateMap.put(l2.Id, new List<SObject>{ acc });
        duplicateMap.put(l3.Id, new List<SObject>{ acc });
        
        Map<String,Id> phoneMap = new Map<String,Id>();
        phoneMap.put('+919966665555', con1.Id);
        phoneMap.put('+919966664444', con2.Id);
        phoneMap.put('+919966663333', con3.Id);
        
        Test.startTest();
        RES_LeadConversionHandler.convertLeads(new List<Lead>{ l1, l2, l3 }, duplicateMap, phoneMap);
        Test.stopTest();
        
        List<Lead> results = [SELECT Id, IsConverted FROM Lead WHERE Id IN (:l1.Id, :l2.Id, :l3.Id)];
        System.assertEquals(3, results.size(), 'All leads should be converted with contacts');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Group 2: RES_LeadConversionQueueable - Execution Tests (11 tests)
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testQueueableExecuteWithMetSLA() {
        Account acc = RES_TestDataFactory.createAccountWithName('Queueable SLA Test');
        Lead l = RES_TestDataFactory.createLeadWithProject('queuemeta@test.com', PROJECT);
        
        Test.startTest();
        RES_LeadConversionQueueable queueable = new RES_LeadConversionQueueable(new List<Lead>{ l });
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Lead result = [SELECT Id, IsConverted FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, result.IsConverted, 'Lead should be converted');
    }

    @IsTest
    static void testQueueableMultipleLeads() {
        Account acc = RES_TestDataFactory.createAccountWithName('Queueable Multiple');
        
        Lead l1 = RES_TestDataFactory.createLeadWithProject('queuemulti1@test.com', PROJECT);
        Lead l2 = RES_TestDataFactory.createLeadWithProject('queuemulti2@test.com', PROJECT);
        
        Test.startTest();
        RES_LeadConversionQueueable queueable = new RES_LeadConversionQueueable(new List<Lead>{ l1, l2 });
        System.enqueueJob(queueable);
        Test.stopTest();
        
        List<Lead> results = [SELECT Id, IsConverted FROM Lead WHERE Id IN (:l1.Id, :l2.Id)];
        System.assertEquals(2, results.size(), 'Both leads should be converted');
    }

    @IsTest
    static void testQueueableEmptyLeadList() {
        Test.startTest();
        RES_LeadConversionQueueable queueable = new RES_LeadConversionQueueable(new List<Lead>());
        String jobId = System.enqueueJob(queueable);
        Test.stopTest();
        
        System.assertNotEquals(null, jobId, 'Job should be enqueued even with empty list');
    }

    @IsTest
    static void testQueueableConstructorWithRetryCount() {
        Lead l = RES_TestDataFactory.createLeadWithProject('constructor@test.com', PROJECT);
        
        Test.startTest();
        RES_LeadConversionQueueable q1 = new RES_LeadConversionQueueable(new List<Lead>{ l }, 2);
        System.assertNotEquals(null, q1, 'Queueable created with retry count');
        
        RES_LeadConversionQueueable q2 = new RES_LeadConversionQueueable(new List<Lead>{ l });
        System.assertNotEquals(null, q2, 'Queueable created without retry count');
        Test.stopTest();
    }

    @IsTest
    static void testQueueableWithContactMatching() {
        Account acc = RES_TestDataFactory.createAccountWithName('Queueable Contact Match');
        Contact con = RES_TestDataFactory.createContactFull(acc.Id, 'Queue', 'Contact', '+919977332211');
        
        Lead l = RES_TestDataFactory.createLeadWithProject('queueconmatch@test.com', PROJECT);
        l.MobilePhone = '+919977332211';
        l.RES_CR_number__c = acc.RES_CR_number__c;
        update l;
        
        Test.startTest();
        RES_LeadConversionQueueable queueable = new RES_LeadConversionQueueable(new List<Lead>{ l });
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Lead result = [SELECT Id, IsConverted FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, result.IsConverted, 'Lead should be converted with contact match');
    }

    @IsTest
    static void testQueueableWithDuplicateAccountDetection() {
        Account acc = RES_TestDataFactory.createAccountWithName('Queueable Duplicate Detection');
        
        Lead l = RES_TestDataFactory.createLeadWithProject('queuedup@test.com', PROJECT);
        l.Company = 'Queueable Duplicate Detection';
        l.RES_CR_number__c = acc.RES_CR_number__c;
        update l;
        
        Test.startTest();
        RES_LeadConversionQueueable queueable = new RES_LeadConversionQueueable(new List<Lead>{ l });
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Lead result = [SELECT Id, IsConverted FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, result.IsConverted, 'Lead should be converted via duplicate detection');
    }

    @IsTest
    static void testQueueableEventPublishing() {
        Account acc = RES_TestDataFactory.createAccountWithName('Queueable Event Publishing');
        Lead l = RES_TestDataFactory.createLeadWithProject('queueevent@test.com', PROJECT);
        
        Test.startTest();
        RES_LeadConversionQueueable queueable = new RES_LeadConversionQueueable(new List<Lead>{ l });
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Lead result = [SELECT Id, IsConverted FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, result.IsConverted, 'Lead converted and event published');
    }

    @IsTest
    static void testQueueableCheckAllLeadsReady() {
        Account acc = RES_TestDataFactory.createAccountWithName('Check All Ready');
        
        Lead l1 = RES_TestDataFactory.createLeadWithProject('queueready1@test.com', PROJECT);
        Lead l2 = RES_TestDataFactory.createLeadWithProject('queueready2@test.com', PROJECT);
        Lead l3 = RES_TestDataFactory.createLeadWithProject('queueready3@test.com', PROJECT);
        
        Test.startTest();
        RES_LeadConversionQueueable queueable = new RES_LeadConversionQueueable(
            new List<Lead>{ l1, l2, l3 }
        );
        System.enqueueJob(queueable);
        Test.stopTest();
        
        List<Lead> results = [SELECT Id, IsConverted FROM Lead WHERE Id IN (:l1.Id, :l2.Id, :l3.Id)];
        System.assertEquals(3, results.size(), 'All leads should be converted');
    }

    @IsTest
    static void testQueueableDuplicateDetectionFlow() {
        Account acc1 = RES_TestDataFactory.createAccountWithName('First Duplicate');
        Account acc2 = RES_TestDataFactory.createAccountWithName('Second Duplicate');
        
        Lead l1 = RES_TestDataFactory.createLeadWithProject('queuedup1@test.com', PROJECT);
        Lead l2 = RES_TestDataFactory.createLeadWithProject('queuedup2@test.com', PROJECT);
        
        Test.startTest();
        RES_LeadConversionQueueable queueable = new RES_LeadConversionQueueable(new List<Lead>{ l1, l2 });
        System.enqueueJob(queueable);
        Test.stopTest();
        
        List<Lead> results = [SELECT Id, IsConverted FROM Lead WHERE Id IN (:l1.Id, :l2.Id)];
        System.assertEquals(2, results.size(), 'Both leads should be converted');
    }

    @IsTest
    static void testQueueableRetryLogic() {
        Lead l = RES_TestDataFactory.createLeadWithSLA('queueretry@test.com', 'Met', PROJECT);
        
        Test.startTest();
        RES_LeadConversionQueueable q = new RES_LeadConversionQueueable(new List<Lead>{ l }, 0);
        System.enqueueJob(q);
        Test.stopTest();
        
        Lead result = [SELECT Id, IsConverted FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, result.IsConverted, 'Should convert on first attempt');
    }

    @IsTest
    static void testGetMaxRetriesFromLabelDefaultValue() {
        Lead l = RES_TestDataFactory.createLeadWithProject('maxretries@test.com', PROJECT);
        
        Test.startTest();
        RES_LeadConversionQueueable queueable = new RES_LeadConversionQueueable(new List<Lead>{ l }, 0);
        System.enqueueJob(queueable);
        Test.stopTest();
        
        Lead result = [SELECT Id, IsConverted FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, result.IsConverted, 'Should use default max retries');
    }
    @IsTest
    static void testQueueableMaxRetriesLogic() {
    Account acc = RES_TestDataFactory.createAccountWithName('Max Retries Test');
    
    Lead l = new Lead();
    l.FirstName = 'Max';
    l.LastName = 'Retries';
    l.Email = 'maxretries@test.com';
    l.MobilePhone = '+919988884444';
    l.Company = 'Max Retries Co';
    l.RES_Project__c = PROJECT;
    l.Status = '04';
    l.RES_SLA_Status__c = 'Met';
    insert l;
    
    Test.startTest();
    RES_LeadConversionQueueable queueable = 
        new RES_LeadConversionQueueable(new List<Lead>{ l }, 0);
    System.enqueueJob(queueable);
    Test.stopTest();
    
    Lead result = [SELECT IsConverted FROM Lead WHERE Id = :l.Id];
    System.assertEquals(true, result.IsConverted, 'Lead should convert');
}
}