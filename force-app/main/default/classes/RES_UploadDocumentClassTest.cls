@IsTest
private class RES_UploadDocumentClassTest {
    @IsTest
    static void testGetFiles() {
        System.runAs(getRunAsUser()) {
            Account acc = RES_TestDataFactory.createAccount();
            ContentVersion cv = RES_TestDataFactory.createFile();

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
    }

    @IsTest
    static void testGetFilesNullRecordId() {
        System.runAs(getRunAsUser()) {
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
    }

    @IsTest
    static void testUploadFiles() {
        System.runAs(getRunAsUser()) {
            Account acc = RES_TestDataFactory.createAccount();
            ContentVersion cv = RES_TestDataFactory.createFile();

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
    }

    @IsTest
    static void testUpdateDocumentLabel() {
        System.runAs(getRunAsUser()) {
            ContentVersion cv = RES_TestDataFactory.createFile();

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
    }

    @IsTest
    static void testDeleteFile() {
        System.runAs(getRunAsUser()) {
            ContentVersion cv = RES_TestDataFactory.createFile();
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

    private static User getRunAsUser() {
        return [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
    }
}