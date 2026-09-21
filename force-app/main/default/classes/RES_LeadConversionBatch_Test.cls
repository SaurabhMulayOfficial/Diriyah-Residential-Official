/**
* ==============================================================================
* Test Class    : RES_LeadConversionBatch_Test
* Description   : Unit tests for RES_LeadConversionBatch.
*                 Test data creation is fully delegated to
*                 RES_TestDataFactory — this class
*                 only contains test assertions and execution logic.
*
* Coverage      :
*
* Author        : Poonam Jain
* Company       : Globant Inc
* Created Date  : 05/05/2025
*@last modified Date : 21/09/2026
* ==============================================================================
*/
@isTest
private class RES_LeadConversionBatch_Test {

    @isTest
    static void testCompanyLeadConverted() {
        Lead l1 = RES_TestDataFactory.createLeadFull(
            'company@example.in', null, 'Test Co', 'Amansamar Residences Wadi Safar', '04', 'Met'
        );
        l1.RES_CR_Number__c = '1290123456';
        l1.RES_Identification_Type__c = 'ZIT04';
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.duplicateRuleHeader.allowSave = true;
        Database.update(l1, dml);

        Test.startTest();
        Database.executeBatch(new RES_LeadConversionBatch(), 200);
        Test.stopTest();

        Lead updated = [SELECT Id, IsConverted FROM Lead WHERE Id = :l1.Id];
        System.assertEquals(true, updated.IsConverted, 'Company lead should be converted');
    }

    @isTest
    static void testIndividualLeadConverted() {
        // Individual (RES_Individual) record type lead — covers the if branch in execute
        Id rtId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
            .get('RES_Individual').getRecordTypeId();
        Lead l1 = new Lead(
            RecordTypeId = rtId,
            FirstName = 'Indiv',
            LastName = 'TestLead',
            Company = 'Indiv Co',
            Email = 'indiv@example.in',
            Status = '04',
            MobilePhone = '+966501234567',
            RES_Project__c = 'Amansamar Residences Wadi Safar',
            RES_SLA_Status__c = 'Met'
        );
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.duplicateRuleHeader.allowSave = true;
        Database.insert(l1, dml);

        Test.startTest();
        Database.executeBatch(new RES_LeadConversionBatch(), 200);
        Test.stopTest();

        Lead updated = [SELECT Id, IsConverted FROM Lead WHERE Id = :l1.Id];
        System.assertEquals(true, updated.IsConverted, 'Individual lead should be converted');
    }

    @isTest
    static void testFinishNoop() {
        Test.startTest();
        new RES_LeadConversionBatch().finish(null);
        Test.stopTest();
    }
}