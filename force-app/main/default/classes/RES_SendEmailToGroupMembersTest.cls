@isTest
public class RES_SendEmailToGroupMembersTest {
	@testSetup
    public static void setupTestData(){
        Test.startTest();
        Account companyAccount = RES_TestDataFactory.createCompanyRTAccount('Globant', '1212121212');
        Id contractRecordTypeId = Schema.SObjectType.Contract
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Contract_Residential_Sales_RT)
            .getRecordTypeId();
        RES_TestDataFactory.createContract(companyAccount.Id, 'Draft', contractRecordTypeId);
        User userObj = RES_TestDataFactory.createSystemAdminUser();
        System.runAs(userObj){
            Group grp = RES_TestDataFactory.createGroup('RES_Finance_Team');
            List<GroupMember> members = RES_TestDataFactory.createGroupMembers(grp.Id, userObj.Id);
        }
        Test.stopTest();
    }
    @isTest
    public static void sendEmailNotificationToGroupMembersTest(){
        Test.startTest();
        List<RES_SendEmailNotificationToGroupMembers.Input> inputsLst = new List<RES_SendEmailNotificationToGroupMembers.Input>();
        List<Contract> contractLst = [ SELECT Id, ContractNumber 
                                       FROM Contract 
                                       WHERE Status = 'Draft' LIMIT 1 ];
        if(!contractLst.isEmpty()){
            Contract contractObj = new Contract(Id = contractLst[0].Id, RES_SIMAH_Form_Received__c = true);
            update contractObj;
            RES_SendEmailNotificationToGroupMembers.Input inputObj = new RES_SendEmailNotificationToGroupMembers.Input();
            List<Group> groupLst = [ SELECT Id, 
                                    (SELECT Id, UserOrGroupId FROM GroupMembers) 
                                     FROM Group 
                                     WHERE DeveloperName = 'RES_Finance_Team' ];
            if(!groupLst.isEmpty()){
                inputObj.groupMembers = groupLst[0].GroupMembers;
                inputObj.contractRecord = contractLst[0];
                inputObj.emailTemplateName = 'RES_SIMAH_Signed_Notification_Template';
                inputsLst.add(inputObj);
                RES_SendEmailNotificationToGroupMembers.sendEmailNotificationToGroupMembers(inputsLst);
                List<EmailMessage> emailLst = [ SELECT Id 
                                                FROM EmailMessage 
                                                WHERE Subject = 'SIMAH Signed' 
                                                LIMIT 1 ];
                Assert.isNotNull(emailLst); 
            }
        }
        Test.stopTest();
    }
}