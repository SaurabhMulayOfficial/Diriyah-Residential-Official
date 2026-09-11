/**
 * @description Test class for RES_BulkFolderUploaderController covering processUploadedFiles and dynamic ProductCode matching.
 */
@isTest
private class RES_BulkFolderUploaderControllerTest {

    @testSetup
    static void setupTestData() {
        List<Product2> testProducts = new List<Product2>();

        Product2 prod1 = new Product2(
            Name = 'Alpha Product Catalog',
            ProductCode = 'PROD001',
            IsActive = true
        );
        testProducts.add(prod1);

        Product2 prod2 = new Product2(
            Name = 'Beta Product Catalog',
            ProductCode = 'PROD002',
            IsActive = true
        );
        testProducts.add(prod2);

        insert testProducts;
    }

    /**
     * Helper method to insert a dummy ContentVersion and return its generated ContentDocumentId.
     */
    private static Id createDummyContentDocument(String title) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf('Sample Test Data Content'),
            IsMajorVersion = true
        );
        insert cv;

        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
    }

    /**
     * @description Tests successful matching and linking of uploaded files to Product2 records.
     */
    @isTest
    static void testProcessUploadedFilesSuccess() {
        Product2 prod1 = [SELECT Id FROM Product2 WHERE ProductCode = 'PROD001' LIMIT 1];
        Product2 prod2 = [SELECT Id FROM Product2 WHERE ProductCode = 'PROD002' LIMIT 1];

        Id doc1Id = createDummyContentDocument('PROD001_Catalog');
        Id doc2Id = createDummyContentDocument('PROD002_Manual');

        List<RES_BulkFolderUploaderController.UploadedFile> files = new List<RES_BulkFolderUploaderController.UploadedFile>();

        RES_BulkFolderUploaderController.UploadedFile file1 = new RES_BulkFolderUploaderController.UploadedFile();
        file1.name = 'PROD001_Catalog.pdf';
        file1.documentId = (String) doc1Id;
        files.add(file1);

        RES_BulkFolderUploaderController.UploadedFile file2 = new RES_BulkFolderUploaderController.UploadedFile();
        file2.name = 'PROD002_Manual.png';
        file2.documentId = (String) doc2Id;
        files.add(file2);

        String jsonPayload = JSON.serialize(files);

        Test.startTest();
        RES_BulkFolderUploaderController.ProcessingResult result = RES_BulkFolderUploaderController.processUploadedFiles(jsonPayload);
        Test.stopTest();

        System.assertEquals(2, result.successCount, 'All valid files should be successfully processed.');
        System.assertEquals(0, result.failedCount, 'No failure count expected.');

        List<ContentDocumentLink> linksProd1 = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :prod1.Id];
        System.assertEquals(1, linksProd1.size(), 'Exactly 1 ContentDocumentLink should be created for PROD001.');

        List<ContentDocumentLink> linksProd2 = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :prod2.Id];
        System.assertEquals(1, linksProd2.size(), 'Exactly 1 ContentDocumentLink should be created for PROD002.');
    }

    /**
     * @description Tests handling when an uploaded filename does not match any existing ProductCode.
     */
    @isTest
    static void testProcessUploadedFilesUnmatchedAndPartialFailures() {
        Id doc1Id = createDummyContentDocument('UNMATCHED_FILE');

        List<RES_BulkFolderUploaderController.UploadedFile> files = new List<RES_BulkFolderUploaderController.UploadedFile>();

        RES_BulkFolderUploaderController.UploadedFile file1 = new RES_BulkFolderUploaderController.UploadedFile();
        file1.name = 'UNKNOWN_CODE.pdf';
        file1.documentId = (String) doc1Id;
        files.add(file1);

        RES_BulkFolderUploaderController.UploadedFile file2 = new RES_BulkFolderUploaderController.UploadedFile();
        file2.name = '';
        file2.documentId = '';
        files.add(file2);

        String jsonPayload = JSON.serialize(files);

        Test.startTest();
        RES_BulkFolderUploaderController.ProcessingResult result = RES_BulkFolderUploaderController.processUploadedFiles(jsonPayload);
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'No links should be created for unmatched or invalid files.');
        System.assertEquals(2, result.failedCount, 'Failed count should match invalid file entries.');
    }

    /**
     * @description Validates exception handling for empty or blank JSON input payloads.
     */
    @isTest
    static void testProcessUploadedFilesExceptions() {
        Boolean blankExceptionThrown = false;
        Boolean emptyListExceptionThrown = false;

        Test.startTest();
        try {
            RES_BulkFolderUploaderController.processUploadedFiles('');
        } catch (AuraHandledException e) {
            blankExceptionThrown = true;
        }

        try {
            RES_BulkFolderUploaderController.processUploadedFiles('[]');
        } catch (AuraHandledException e) {
            emptyListExceptionThrown = true;
        }
        Test.stopTest();

        System.assert(blankExceptionThrown, 'Exception expected when payload string is blank.');
        System.assert(emptyListExceptionThrown, 'Exception expected when payload deserializes to an empty list.');
    }
}