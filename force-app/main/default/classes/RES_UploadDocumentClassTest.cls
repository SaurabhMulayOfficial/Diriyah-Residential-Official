@IsTest
private class RES_UploadDocumentClassTest {
    @testSetup
    static void setupData() {
        Account acc = RES_TestDataFactory.createAccount();
        ContentVersion cv = RES_TestDataFactory.createFile();
    }
    
    @isTest
    static void testGetCurrentUserRoleName() {
        
        User u = RES_TestDataFactory.createSalesRepUser();
        Boolean checkForDocumentLabelEdit;
        Test.startTest();
        System.runAs(u) {
            checkForDocumentLabelEdit = RES_UploadDocumentClass.canEditDocumentLabel();
        }
        Test.stopTest();
        
        System.assertEquals(
            true,
            checkForDocumentLabelEdit,
            'Method should safely return true for Specialist'
        );
    }
    
    
    @IsTest
    static void testGetFiles() {
        
        Account acc  = [SELECT Id From Account LIMIT 1];
        ContentVersion cv = [SELECT Id,ContentDocumentId From ContentVersion LIMIT 1];
        
        
        RES_TestDataFactory.createDocLink(acc.Id, cv.ContentDocumentId);
        
        Test.startTest();
        List<RES_UploadDocumentClass.FileRow> files =
            RES_UploadDocumentClass.getFiles(acc.Id);
        Test.stopTest();
        
        System.assertEquals(
            1,
            files.size(),
            'One linked file should be returned.'
        );
        System.assertEquals(
            cv.ContentDocumentId,
            files[0].contentDocumentId,
            'Returned ContentDocumentId should match the uploaded file.'
        );
        System.assertEquals(
            'TestFile',
            files[0].fileName,
            'Returned file name should match the ContentVersion title.'
        );
        
    }
    
    @IsTest
    static void testGetFilesNullRecordId() {
        
        Test.startTest();
        List<RES_UploadDocumentClass.FileRow> files =
            RES_UploadDocumentClass.getFiles(null);
        Test.stopTest();
        
        System.assertEquals(
            0,
            files.size(),
            'No files should be returned when record Id is null.'
        );
        
    }
    
    @IsTest
    static void testUploadFiles() {
        
        Account acc  = [SELECT Id From Account LIMIT 1];
        ContentVersion cv = [SELECT Id,ContentDocumentId From ContentVersion LIMIT 1];
        
        
        RES_UploadDocumentClass.UploadFileWrapper wrapper =
            new RES_UploadDocumentClass.UploadFileWrapper();
        
        wrapper.documentId = cv.ContentDocumentId;
        wrapper.fileName = 'TestFile.pdf';
        wrapper.documentLabel = 'Passport';
        wrapper.attachmentType = 'Passport';
        
        Test.startTest();
        RES_UploadDocumentClass.uploadFiles(
            acc.Id,
            new List<RES_UploadDocumentClass.UploadFileWrapper>{ wrapper }
        );
        Test.stopTest();
        
        ContentDocumentLink linkRec = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :acc.Id
            AND ContentDocumentId = :cv.ContentDocumentId
            LIMIT 1
        ];
        
        System.assertNotEquals(
            null,
            linkRec,
            'ContentDocumentLink should be created for uploaded file.'
        );
        
    }
    
    @IsTest
    static void testUpdateDocumentLabel() {
        
        ContentVersion cv = [SELECT Id,ContentDocumentId From ContentVersion LIMIT 1];
        
        Test.startTest();
        RES_UploadDocumentClass.updateDocumentLabel(
            cv.Id,
            'National Id'
        );
        Test.stopTest();
        
        ContentVersion updatedCv = [
            SELECT RES_Document_Label__c
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
        
        System.assertEquals(
            'National Id',
            updatedCv.RES_Document_Label__c,
            'Document label should be updated on ContentVersion.'
        );
        
    }
    
    @IsTest
    static void testDeleteFile() {
        
        ContentVersion cv = [SELECT Id,ContentDocumentId From ContentVersion LIMIT 1];
        
        Id docId = cv.ContentDocumentId;
        
        Test.startTest();
        RES_UploadDocumentClass.deleteFile(docId);
        Test.stopTest();
        
        Integer countDocs = [
            SELECT Count()
            FROM ContentDocument
            WHERE Id = :docId
        ];
        
        System.assertEquals(
            0,
            countDocs,
            'ContentDocument should be deleted.'
        );
    }
    
}