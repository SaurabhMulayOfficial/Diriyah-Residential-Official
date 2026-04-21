@isTest
public class RES_ReassignmentLogicHandlerTest {

    @isTest
    static void testLeadReassignment_RoundRobin() {

        User u1 = RES_TestDataFactory.createSalesManagerUser();
        User u2 = RES_TestDataFactory.createSalesDirectorUser();
        List<Lead> leads = new List<Lead>();

        System.runAs(u1){
            Group queue = new Group(
                Name = 'Test Queue',
                Type = 'Queue'
            );
            insert queue;

            insert new QueueSobject(
                QueueId = queue.Id,
                SObjectType = 'Lead'
            );

            RecordType rt = [SELECT Id, DeveloperName 
                            FROM RecordType 
                            WHERE SObjectType = 'Lead' 
                            LIMIT 1];

            RES_Assignment_Config__c config = new RES_Assignment_Config__c(
                Name = 'Test Config',
                RES_Record_Types__c = rt.DeveloperName,
                RES_Channel__c = 'Z09',
                RES_Queue__c = queue.Name
            );
            insert config;

            RES_Assignment_Rule__c rule1 = new RES_Assignment_Rule__c(
                RES_Assignment_Config__c = config.Id,
                RES_User__c = u1.Id,
                RES_User_Availability_Status__c = 'Available',
                RES_Order__c = 1,
                RES_Capacity__c = 2,
                RES_Lead_Count__c = 0,
                RES_Last_Assigned__c = true
            );

            RES_Assignment_Rule__c rule2 = new RES_Assignment_Rule__c(
                RES_Assignment_Config__c = config.Id,
                RES_User__c = u2.Id,
                RES_User_Availability_Status__c = 'Available',
                RES_Order__c = 2,
                RES_Capacity__c = 2,
                RES_Lead_Count__c = 0,
                RES_Last_Assigned__c = false
            );

            insert new List<RES_Assignment_Rule__c>{rule1, rule2};

            for(Integer i = 0; i < 4; i++){
                leads.add(new Lead(
                    LastName = 'Test ' + i,
                    Company = 'ABC',
                    LeadSource = 'Z09',
                    RecordTypeId = rt.Id,
                    MobilePhone = '+123123123'+i
                ));
            }

            insert leads;
        }


        Test.startTest();
        RES_ReassignmentLogicHandler.runLeadReassignment(leads, new List<RES_ReassignmentLogicHandler.leadRoutingWrapper>());
        Test.stopTest();

        List<Lead> updatedLeads = [SELECT Id, OwnerId FROM Lead WHERE Id IN :leads];

        Integer countU1 = 0;
        Integer countU2 = 0;

        for(Lead l : updatedLeads){
            if(l.OwnerId == u1.Id) countU1++;
            if(l.OwnerId == u2.Id) countU2++;
        }

        System.assertEquals(2, countU1, 'User1 should get 2 leads');
        System.assertEquals(2, countU2, 'User2 should get 2 leads');

        System.runAs(u1){

            RES_UserAvailabilityController.updateUserStatus('Offline');
            RES_UserAvailabilityController.getUserStatus();
            
            System.assertEquals('Offline', RES_UserAvailabilityController.getUserStatus(), 'User1 status should be Offline');
        }

    }
}