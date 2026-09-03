/**
 * @description Test class for RES_BulkFolderUploaderController covering global dynamic ProductCode matching.
 */
@isTest
private class RES_BulkFolderUploaderControllerTest {

    @testSetup
    static void setupTestData() {
        // Create sample target Product records with distinct ProductCodes
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
     * @description Validates successful file upload and automatic linking across multiple products using exact and prefix matching.
     */
    @isTest
    static void testUploadAndAttachFilesToProductSuccess() {
        Product2 prod1 = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'PROD001' LIMIT 1];
        Product2 prod2 = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'PROD002' LIMIT 1];

        List<RES_BulkFolderUploaderController.FilePayload> payloads = new List<RES_BulkFolderUploaderController.FilePayload>();

        // File 1: Exact match for PROD001
        RES_BulkFolderUploaderController.FilePayload file1 = new RES_BulkFolderUploaderController.FilePayload();
        file1.fileName = 'PROD001.pdf';
        file1.base64Data = EncodingUtil.base64Encode(Blob.valueOf('Test Content PDF 1'));
        payloads.add(file1);

        // File 2: Variant prefix match for PROD001 ("PROD001-v2.pdf" starts with "PROD001")
        RES_BulkFolderUploaderController.FilePayload file2 = new RES_BulkFolderUploaderController.FilePayload();
        file2.fileName = 'PROD001-v2.pdf';
        file2.base64Data = EncodingUtil.base64Encode(Blob.valueOf('Test Content PDF 2'));
        payloads.add(file2);

        // File 3: Match for PROD002
        RES_BulkFolderUploaderController.FilePayload file3 = new RES_BulkFolderUploaderController.FilePayload();
        file3.fileName = 'PROD002_Manual.png';
        file3.base64Data = EncodingUtil.base64Encode(Blob.valueOf('Test Content PNG'));
        payloads.add(file3);

        Test.startTest();
        String resultMsg = RES_BulkFolderUploaderController.uploadAndAttachFilesToProduct(payloads);
        Test.stopTest();

        // Verify return message
        System.assertEquals('3 file(s) successfully attached across matched Product records.', resultMsg, 'Result message should confirm 3 files attached.');

        // Verify 2 ContentDocumentLinks created for PROD001
        List<ContentDocumentLink> linksProd1 = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :prod1.Id
        ];
        System.assertEquals(2, linksProd1.size(), 'Two ContentDocumentLinks should be linked to PROD001.');

        // Verify 1 ContentDocumentLink created for PROD002
        List<ContentDocumentLink> linksProd2 = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :prod2.Id
        ];
        System.assertEquals(1, linksProd2.size(), 'One ContentDocumentLink should be linked to PROD002.');
    }

    /**
     * @description Validates exception handling when uploaded filenames do not match any existing ProductCode.
     */
    @isTest
    static void testUploadWithUnmatchedProductCodes() {
        List<RES_BulkFolderUploaderController.FilePayload> payloads = new List<RES_BulkFolderUploaderController.FilePayload>();

        RES_BulkFolderUploaderController.FilePayload file1 = new RES_BulkFolderUploaderController.FilePayload();
        file1.fileName = 'UNKNOWN_CODE_DOC.pdf';
        file1.base64Data = EncodingUtil.base64Encode(Blob.valueOf('Unmatched Sample Data'));
        payloads.add(file1);

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            RES_BulkFolderUploaderController.uploadAndAttachFilesToProduct(payloads);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected AuraHandledException should be thrown when no file names match product codes.');
    }

    /**
     * @description Validates exception handling when filePayloads list is empty or null.
     */
    @isTest
    static void testUploadWithEmptyPayloads() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            RES_BulkFolderUploaderController.uploadAndAttachFilesToProduct(new List<RES_BulkFolderUploaderController.FilePayload>());
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected AuraHandledException should be thrown for empty file payload list.');
    }
}