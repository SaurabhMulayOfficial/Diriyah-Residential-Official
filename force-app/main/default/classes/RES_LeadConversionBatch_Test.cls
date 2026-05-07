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
* Created Date  : May 5, 2025
* ==============================================================================
*/
@isTest
private class RES_LeadConversionBatch_Test {
    
    @isTest
    static void testLeadQualified() {
        
        Lead l1 = RES_TestDataFactory.createLead('test@example.in');
        l1.Status = '04';
        l1.RES_CR_Number__c = '1290123456';
        update l1;
        
        List<Lead> leads = new List<Lead>();
        leads.add(l1);
        
        Test.startTest(); 
        RES_LeadConversionBatch batch = new RES_LeadConversionBatch();
        Database.executeBatch(batch, 1);
        Test.stopTest();
        
        // Verify Leads Converted
        List<Lead> updatedLeads = [
            SELECT Id, IsConverted 
            FROM Lead 
            WHERE Id IN :leads
        ];
        
        System.assertEquals(1, updatedLeads.size(), 'Lead should be queried');
        
        for (Lead l : updatedLeads) {
            System.assertEquals(true, l.IsConverted, 'Lead should be converted');
        }
        
    }
    
}