/**
* @class name         : RES_LeadRetirementBatchTest
* @description        : Test class for RES_LeadRetirementBatch and RES_LeadRetirementScheduler.
* @created date       : 16/02/2026
* @last modified Date : 18/02/2026
* @author             : Nitin Marathe
*/

@isTest
private class RES_LeadRetirementBatchTest {
    
    @testSetup
    static void setup() {
        // 1. Setup Custom Setting threshold (6 months)
        DIR_Lead_Retirement_Configuration__c config = new DIR_Lead_Retirement_Configuration__c(
            DIR_Retirement_Day_Threshold__c = 30
        );
        insert config;
        
        // 2. Query Record Type IDs using DeveloperName
        Id companyRtId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('RES_Company').getRecordTypeId();
        Id individualRtId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('RES_Individual').getRecordTypeId();
        
        // 3. Create Leads (Mixed Record Types)
        List<Lead> leadsToInsert = new List<Lead>();
        for(Integer i = 0; i < 10; i++) {
            leadsToInsert.add(new Lead(
                LastName = 'TestLead' + i,
                Company = 'TestCompany' + i,
                Status = '01',
                RecordTypeId = (Math.mod(i, 2) == 0) ? companyRtId : individualRtId
            ));
        }
        insert leadsToInsert;
        
        // 4. Backdate 5 records to be > 6 months old (approx 210 days)
        // We use Test.setCreatedDate because LastModifiedDate is system-managed
        for(Integer i = 0; i < 5; i++) {
            Test.setCreatedDate(leadsToInsert[i].Id, DateTime.now().addDays(-60));
        }
    }
    
    @isTest
    static void testBatchExecution() {
        // Ensure the batch class has the Test.isRunningTest() logic to use CreatedDate
        Test.startTest();
        RES_LeadRetirementBatch batch = new RES_LeadRetirementBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest(); // Forces asynchronous batch to complete
        
        // Assertions: Validate that the 5 backdated records were retired
        Integer retiredCount = [SELECT count() FROM Lead WHERE Status = '05'];
        System.assertEquals(5, retiredCount, 'Exactly 5 Leads should have been moved to Retired status.');
        
        // Validate that the other 5 records remained 'New'
        Integer newCount = [SELECT count() FROM Lead WHERE Status = '01'];
        System.assertEquals(5, newCount, '5 recent Leads should remain in New status.');
    }
    
    @isTest
    static void testSchedulerExecution() {
        // Define a cron expression for the scheduler (Daily at 1 AM)
        String cronExp = '0 0 1 * * ?'; 
        
        Test.startTest();
        // Schedule the job
        String jobId = System.schedule('Test_RES_LeadRetirementScheduler', cronExp, new RES_LeadRetirementScheduler());
        Test.stopTest();
        
        // Verify the job exists in the system
        CronTrigger ct = [SELECT Id, CronExpression, TimesTriggered, State FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(cronExp, ct.CronExpression, 'The scheduled cron expression must match.');
        System.assertNotEquals(null, jobId, 'The scheduler should have returned a valid Job ID.');
    }
}