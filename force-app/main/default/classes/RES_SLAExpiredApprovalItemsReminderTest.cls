@isTest
public class RES_SLAExpiredApprovalItemsReminderTest {
	@testSetup
    public static void setupData(){
        Test.startTest();
        Account companyAccount = RES_TestDataFactory.createCompanyRTAccount('Globant', '1212121212');
        Id contractRecordTypeId = Schema.SObjectType.Contract
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Contract_Residential_Sales_RT)
            .getRecordTypeId();
        Contract contractObj = RES_TestDataFactory.createContract(companyAccount.Id, 'Draft', contractRecordTypeId);
        User adminUser = RES_TestDataFactory.createSystemAdminUser();
        
        System.runAs(adminUser) {
            Group financeGroup = RES_TestDataFactory.createGroup('RES_Finance_Team_Group');
            RES_TestDataFactory.createGroupMembers(financeGroup.Id, adminUser.Id);
        }
        
        Test.stopTest();
    }
    
    @isTest
    public static void testSendDailyRemindersToSLAExpiredApprovalWorkItems(){
        Test.startTest();
        List<Contract> contractLst = [ SELECT Id FROM Contract WHERE Status = 'Draft' ];
        List<Group> financeGroup = [ SELECT Id FROM Group WHERE DeveloperName = 'RES_Finance_Team_Group' ];
        if(!contractLst.isEmpty()){
            RES_SLAExpiredApprovalItemsReminder.Input input = new RES_SLAExpiredApprovalItemsReminder.Input();
            List<RES_SLAExpiredApprovalItemsReminder.Input> inputLst = new List<RES_SLAExpiredApprovalItemsReminder.Input>();
            List<ApprovalWorkItem> approvalWorkItemsLst = new List<ApprovalWorkItem>();
            ApprovalWorkItem workItem = new ApprovalWorkItem(Id = '9jR9X000007MzonUAC', Status = 'Assigned', RES_SLA_End_Date__c = System.NOW(), RelatedRecordId = contractLst[0].Id, RelatedRecordObjectName = 'Contract', AssignedToId = financeGroup[0].Id);
        	approvalWorkItemsLst.add(workItem);
            input.approvalWorkItemsLst = approvalWorkItemsLst;
            inputLst.add(input);
            RES_SLAExpiredApprovalItemsReminder.sendDailyRemindersToSLAExpiredApprovalWorkItems(inputLst);
            List<EmailMessage> emailLst = [ SELECT Id FROM EmailMessage WHERE Subject = 'Approval Work Item Pending Approval' ];
            Assert.isNotNull(emailLst, 'Reminder email sent successfully');
        }
        Test.stopTest();
    }
}