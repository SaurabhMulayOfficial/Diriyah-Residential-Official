/**
 * @description Test class for RES_ContentVersionServices, RES_ContentVersionTriggerHandler,
 * and RES_ContentDocumentTriggerHandler. Validates primary image assignment, unchecking previous primary images,
 * and clearing DisplayUrl upon file deletion.
 */
@isTest
private class RES_ContentVersionServicesTest {

    @testSetup
    static void setupTestData() {
        // Initialize Org Config Switch
        RES_Config_Switch__c config = new RES_Config_Switch__c(
            RES_Triggers_Off__c = false
        );
        insert config;

        // Create test Product record
        Product2 testProduct = new Product2(
            Name = 'Test Catalog Product',
            IsActive = true
        );
        insert testProduct;

        // Create initial ContentVersion (File 1)
        ContentVersion cv1 = new ContentVersion(
            Title = 'Product Image 1',
            PathOnClient = 'ProductImage1.jpg',
            VersionData = Blob.valueOf('Test Image Binary 1'),
            IsMajorVersion = true,
            RES_Want_this_as_product_Image__c = false
        );
        insert cv1;

        // Retrieve generated ContentDocument ID
        Id docId1 = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv1.Id].ContentDocumentId;

        // Link File 1 to the Product2 record
        ContentDocumentLink cdl1 = new ContentDocumentLink(
            ContentDocumentId = docId1,
            LinkedEntityId = testProduct.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl1;
    }

    /**
     * @description Validates checking primary image on update updates Product2 DisplayUrl.
     */
    @isTest
    static void testSetPrimaryImageOnUpdate() {
        Product2 prod = [SELECT Id, DisplayUrl FROM Product2 LIMIT 1];
        ContentVersion cv = [SELECT Id, RES_Want_this_as_product_Image__c FROM ContentVersion LIMIT 1];

        Test.startTest();
        cv.RES_Want_this_as_product_Image__c = true;
        update cv;
        Test.stopTest();

        Product2 updatedProd = [SELECT Id, DisplayUrl FROM Product2 WHERE Id = :prod.Id];
        System.assert(String.isNotBlank(updatedProd.DisplayUrl), 'Product DisplayUrl should be populated.');
        System.assert(updatedProd.DisplayUrl.contains(cv.Id), 'DisplayUrl should contain ContentVersion ID.');
    }

    /**
     * @description Validates inserting a new file directly marked as primary image unchecks previous primary images.
     */
    @isTest
    static void testInsertNewPrimaryImageUnchecksPrevious() {
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        ContentVersion firstCv = [SELECT Id FROM ContentVersion LIMIT 1];

        // Mark first image as primary
        firstCv.RES_Want_this_as_product_Image__c = true;
        update firstCv;

        // Create second file linked to same Product
        ContentVersion secondCv = new ContentVersion(
            Title = 'Product Image 2',
            PathOnClient = 'ProductImage2.jpg',
            VersionData = Blob.valueOf('Test Image Binary 2'),
            IsMajorVersion = true,
            RES_Want_this_as_product_Image__c = false
        );
        insert secondCv;

        Id secondDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :secondCv.Id].ContentDocumentId;

        ContentDocumentLink cdl2 = new ContentDocumentLink(
            ContentDocumentId = secondDocId,
            LinkedEntityId = prod.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl2;

        Test.startTest();
        // Mark second image as primary
        secondCv.RES_Want_this_as_product_Image__c = true;
        update secondCv;
        Test.stopTest();

        // Verify first image was automatically unchecked
        ContentVersion recheckedFirstCv = [SELECT RES_Want_this_as_product_Image__c FROM ContentVersion WHERE Id = :firstCv.Id];
        System.assertEquals(false, recheckedFirstCv.RES_Want_this_as_product_Image__c, 'Previous primary image should be unchecked.');

        // Verify DisplayUrl updated to new version ID
        Product2 updatedProd = [SELECT DisplayUrl FROM Product2 WHERE Id = :prod.Id];
        System.assert(updatedProd.DisplayUrl.contains(secondCv.Id), 'DisplayUrl should point to the newly checked version.');
    }

    /**
     * @description Validates unchecking primary image clears Product2 DisplayUrl.
     */
    @isTest
    static void testUncheckPrimaryImageClearsDisplayUrl() {
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        ContentVersion cv = [SELECT Id FROM ContentVersion LIMIT 1];

        // First set to true
        cv.RES_Want_this_as_product_Image__c = true;
        update cv;

        Test.startTest();
        // Uncheck primary image
        cv.RES_Want_this_as_product_Image__c = false;
        update cv;
        Test.stopTest();

        Product2 updatedProd = [SELECT DisplayUrl FROM Product2 WHERE Id = :prod.Id];
        System.assertEquals(null, updatedProd.DisplayUrl, 'Product DisplayUrl should be cleared when primary image is unchecked.');
    }

    /**
     * @description Validates deleting a ContentDocument marked as primary image clears Product2 DisplayUrl.
     */
    @isTest
    static void testDeletePrimaryImageClearsProductDisplayUrl() {
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];

        // Mark as primary image
        cv.RES_Want_this_as_product_Image__c = true;
        update cv;

        // Verify DisplayUrl was populated
        Product2 initialProd = [SELECT DisplayUrl FROM Product2 WHERE Id = :prod.Id];
        System.assert(String.isNotBlank(initialProd.DisplayUrl), 'DisplayUrl should initially be populated.');

        Test.startTest();
        // Delete ContentDocument record
        ContentDocument docToDelete = [SELECT Id FROM ContentDocument WHERE Id = :cv.ContentDocumentId];
        delete docToDelete;
        Test.stopTest();

        Product2 updatedProd = [SELECT DisplayUrl FROM Product2 WHERE Id = :prod.Id];
        System.assertEquals(null, updatedProd.DisplayUrl, 'Product DisplayUrl should be cleared after primary image document is deleted.');
    }

    /**
     * @description Validates null/empty collection handling across all service methods for defensive code coverage.
     */
    @isTest
    static void testNullAndEmptyGuards() {
        Test.startTest();
        // Call services directly with null and empty parameters to cover guard statements
        RES_ContentVersionServices.handleProductImageUpdates(null, null, true);
        RES_ContentVersionServices.handleProductImageUpdates(new List<ContentVersion>(), null, true);
        
        RES_ContentVersionServices.prepareProductImageDeletion(null);
        RES_ContentVersionServices.prepareProductImageDeletion(new Map<Id, ContentDocument>());
        
        RES_ContentVersionServices.executeProductImageDeletion();
        Test.stopTest();

        System.assertEquals(false, RES_ContentVersionServices.isExecuting, 'Recursion flag should remain false.');
    }
}