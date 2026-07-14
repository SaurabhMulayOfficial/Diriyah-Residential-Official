@IsTest
private class RES_ProcessAttachmentServiceTest {
    @IsTest
    static void testUpdateAttachmentFlag() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contract con = new Contract(
            AccountId = acc.Id,
            Status = 'Draft',
            StartDate = Date.today()
        );
        insert con;

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
}