@IsTest
private class RES_ProcessAttachmentServiceTest {
    @testSetup
    public static void setupTestData(){
        Test.startTest();
        Account companyAccount = RES_TestDataFactory.createCompanyRTAccount('Globant', '1212121212');
        Id contractRecordTypeId = Schema.SObjectType.Contract
            .getRecordTypeInfosByDeveloperName()
            .get(System.Label.RES_Contract_Residential_Sales_RT)
            .getRecordTypeId();
        Contract contractObj = RES_TestDataFactory.createContract(companyAccount.Id, 'Draft', contractRecordTypeId);
        ContentVersion cv1 = RES_TestDataFactory.createContentVersionWithAttachmentType('Signed URC');
        ContentVersion cv2 = RES_TestDataFactory.createContentVersionWithAttachmentType('Signed URC');
        RES_TestDataFactory.createDocLinkForContract(contractObj.Id, cv1.ContentDocumentId);
        RES_TestDataFactory.createDocLinkForContract(contractObj.Id, cv2.ContentDocumentId);
        Test.stopTest();
    }
    @isTest
    public static void testUpdateAttachmentFlag() {
        
        Contract con = [SELECT Id FROM Contract LIMIT 1];

        Test.startTest();
        RES_Process_Attachment__e event = new RES_Process_Attachment__e(
            RES_Object_Name__c = 'Contract',
            RES_recordId__c = con.Id,
            RES_Action__c = 'Update',
            RES_Attachment_Type__c = 'Signed URC'
        );

        Database.SaveResult sr = EventBus.publish(event);

        System.assert(sr.isSuccess());

        Test.stopTest();

        Contract updated = [
            SELECT RES_URC_Signed__c
            FROM Contract
            WHERE Id = :con.Id
        ];
        
        System.assertEquals(true, updated.RES_URC_Signed__c);
    }
    
    @isTest
    public static void testDelete() {
        Contract con = [SELECT Id FROM Contract LIMIT 1];
        Test.startTest();
        RES_Process_Attachment__e event = new RES_Process_Attachment__e(
            RES_Object_Name__c = 'Contract',
            RES_recordId__c = con.Id,
            RES_Action__c = 'Delete',
            RES_Attachment_Type__c = 'Signed URC'
        );
        
        Database.SaveResult sr = EventBus.publish(event);
        
        System.assert(sr.isSuccess());
        Contract updated = [
            SELECT RES_URC_Signed__c
            FROM Contract
            WHERE Id = :con.Id
        ];
        
        System.assertEquals(false, updated.RES_URC_Signed__c);
        Test.stopTest();
    }
}