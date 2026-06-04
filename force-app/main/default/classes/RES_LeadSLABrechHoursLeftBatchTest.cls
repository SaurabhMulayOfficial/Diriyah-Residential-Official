/**
* ==============================================================================
* Test Class    :  RES_LeadSLABrechHoursLeftBatchTest
* Description   : Unit tests for  RES_LeadSLABrechHoursLeftBatch.
*                 Test data creation is fully delegated to
*                 RES_TestDataFactory — this class
*                 only contains test assertions and execution logic.
*
* Coverage      :
*
* Author        : Poonam Jain
* Company       : Globant Inc
* Created Date  : 01/06/2026
* ==============================================================================
*/
@isTest
private class  RES_LeadSLABrechHoursLeftBatchTest {
    
    @isTest
    static void testLeadQualified() {
        
        Lead l1 = RES_TestDataFactory.createLead('test@example.in');
        l1.Status = '01';
        l1.RES_SLA_Due_Time__c = System.now().addHours(5);
        l1.RES_SLA_Status__c = 'Running';
        update l1;
        
        List<Lead> leads = new List<Lead>();
        leads.add(l1);
        
        Test.startTest(); 
        RES_LeadSLABrechHoursLeftBatch batch = new RES_LeadSLABrechHoursLeftBatch();
        Database.executeBatch(batch, 1);
      
        String cronExp = '0 0 * * * ?';

        System.schedule(
            'Test Lead SLA Scheduler',
            cronExp,
            batch);

    
        Test.stopTest();
        
        // Verify Leads Converted
        List<Lead> updatedLeads = [
            SELECT Id, RES_SLA_Hours_Remaining__c 
            FROM Lead 
            WHERE Id IN :leads
        ];
        
        System.assertEquals(1, updatedLeads.size(), 'Lead should be queried');
        
        for (Lead l : updatedLeads) {
            System.assertNotEquals(null, l.RES_SLA_Hours_Remaining__c, 'Not Null');
            
        }
        
    }
    
}