/**
 * @description Test class for RES_BulkFolderUploaderController covering sequential chunking and global dynamic ProductCode matching.
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
     * @description Tests uploading a single-chunk file that successfully matches PROD001 and creates a ContentDocumentLink.
     */
    @isTest
    static void testSaveFileChunkSingleChunkSuccess() {
        Product2 prod1 = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'PROD001' LIMIT 1];

        String fileName = 'PROD001.pdf';
        String base64Data = EncodingUtil.base64Encode(Blob.valueOf('Test Content PDF Single Chunk'));

        Test.startTest();
        String docId = RES_BulkFolderUploaderController.saveFileChunk(fileName, base64Data, null);
        Test.stopTest();

        System.assert(String.isNotBlank(docId), 'ContentDocumentId should be returned on successful chunk upload.');

        // Verify ContentDocumentLink created for PROD001
        List<ContentDocumentLink> links = [
            SELECT Id, LinkedEntityId, ContentDocumentId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :prod1.Id
        ];
        System.assertEquals(1, links.size(), 'One ContentDocumentLink should be linked to PROD001.');
        System.assertEquals(docId, links[0].ContentDocumentId, 'Linked ContentDocumentId must match returned document ID.');
    }

    /**
     * @description Tests uploading a multi-chunk file (First chunk creates doc & links product; second chunk appends new version under same ContentDocumentId).
     */
    @isTest
    static void testSaveFileChunkMultiChunkSuccess() {
        Product2 prod2 = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'PROD002' LIMIT 1];

        String fileName = 'PROD002_Manual.png';
        String chunk1 = EncodingUtil.base64Encode(Blob.valueOf('Chunk 1 Data'));
        String chunk2 = EncodingUtil.base64Encode(Blob.valueOf('Chunk 2 Data'));

        Test.startTest();
        // Chunk 1 Call
        String docId = RES_BulkFolderUploaderController.saveFileChunk(fileName, chunk1, null);
        
        // Chunk 2 Call passing returned docId
        String secondChunkDocId = RES_BulkFolderUploaderController.saveFileChunk(fileName, chunk2, docId);
        Test.stopTest();

        System.assertEquals(docId, secondChunkDocId, 'Document ID should remain identical across chunk iterations.');

        // Verify total ContentVersions created under this ContentDocumentId
        List<ContentVersion> cvList = [
            SELECT Id, ContentDocumentId 
            FROM ContentVersion 
            WHERE ContentDocumentId = :docId
        ];
        System.assertEquals(2, cvList.size(), 'Two ContentVersion records should exist under the same ContentDocumentId.');

        // Verify ContentDocumentLink created for PROD002
        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :prod2.Id
        ];
        System.assertEquals(1, links.size(), 'Exactly one ContentDocumentLink should be created for PROD002.');
    }

    /**
     * @description Validates exception handling when uploaded filename does not match any existing ProductCode.
     */
    @isTest
    static void testSaveFileChunkUnmatchedProductCode() {
        String fileName = 'UNKNOWN_CODE_DOC.pdf';
        String base64Data = EncodingUtil.base64Encode(Blob.valueOf('Unmatched Sample Data'));

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            RES_BulkFolderUploaderController.saveFileChunk(fileName, base64Data, null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected AuraHandledException should be thrown when filename does not match any Product Code.');
    }
}