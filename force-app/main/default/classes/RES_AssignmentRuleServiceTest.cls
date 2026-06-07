@isTest
public with sharing class RES_AssignmentRuleServiceTest {
    public RES_AssignmentRuleServiceTest() {}

    @TestSetup
    static void createData(){
        User u = RES_TestDataFactory.createSalesManagerUser();

        System.runAs(u){
            RES_Assignment_Config__c config = new RES_Assignment_Config__c(
                RES_Record_Types__c = 'RES_Individual;RES_Company',
                RES_Queue__c = 'RES_DG_Teams',
                RES_Condition__c = '1'
            );
            insert config;

            RES_Assignment_Condition__c c = new RES_Assignment_Condition__c(RES_Assignment_Config__c = config.Id,RES_Field_Api_Name__c='leadSource', RES_Operator__c = 'Equal To', RES_Order__c = 1, RES_Value__c = 'Z06');
            insert c;

            RES_Assignment_Workload__c workload = new RES_Assignment_Workload__c(RES_User__c = u.Id, RES_Capacity__c = 2);
            insert workload;

            RES_Assignment_Rule__c rule1 = new RES_Assignment_Rule__c(RES_Assignment_Config__c = config.Id,  RES_Last_Assigned__c = true, RES_Order__c = 1, RES_User_Availability_Status__c = 'Available', RES_User_Workload__c = workload.Id);
            insert rule1;

            Group q = new Group(
                Name = 'RES_DG_Teams',
                DeveloperName = 'RES_DG_Teams',
                Type = 'Queue'
            );

            insert q;

            QueueSobject qs = new QueueSobject(
                QueueId = q.Id,
                SobjectType = 'Lead'
            );

            insert qs;
        }
    }


    @isTest
    static void testRoundRobinAssignment(){
        User u = [SELECT Id From User WHERE username = 'res.salesmanager.test@example.com.sandbox' LIMIT 1];
        Lead l = RES_TestDataFactory.createLead('test.lead@glo.com', 'Z06', UserInfo.getUserId());

        l = [SELECT OwnerId FROM Lead WHERE Id = :l.Id];
        System.AssertEquals(u.Id, l.OwnerId, 'Lead should be assigned to the only available user');

        l.Status = '05';
        update l;
    }


    @isTest
    static void testReassignmentChannel(){

        Group q = [SELECT Id FROM Group WHERE DeveloperName = 'RES_DG_Teams' LIMIT 1];
        Lead l1 = RES_TestDataFactory.createLead('tests.Jk@gslo.com', 'Z05', q.Id);
        Lead l2 = RES_TestDataFactory.createLead('tests.lead@gslo.com', 'Z05', q.Id);

        l1.leadSource = 'Z06';
        l2.leadSource = 'Z06';
        update new List<Lead>{l1, l2};

        Test.startTest();
            EventBus.publish(new RES_Lead_Distribution__e(RES_Queue__c = 'RES_DG_Teams'));
        Test.stopTest();
        
        System.assertEquals(l1.OwnerId, l2.OwnerId, 'Both leads should be assigned to the same user as capacity is 4');

    }
}