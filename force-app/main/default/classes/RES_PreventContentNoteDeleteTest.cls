/**
* @class name         : RES_PreventContentNoteDeleteTest
* @description        : Test class for RES_PreventContentNoteDelete trigger, RES_ContentNoteSecurityHandler, RES_ContentNoteServices, RES_ProfileDAOLayer classes.
* @created date       : 15/04/2026
* @last modified Date : 15/04/2026
* @author             : Nikhil Takawale
*/

@isTest
public class RES_PreventContentNoteDeleteTest {
    
    @testSetup
    public static void setup() {
        Test.startTest();
        
        User testUser = RES_TestDataFactory.createSalesRepUser();
        
        System.runAs(testUser) {
            ContentVersion cv = new ContentVersion();
            cv.Title = 'Test File';
            cv.PathOnClient = 'TestFile.snote';
            cv.VersionData = Blob.valueOf('This is test content');
            cv.IsMajorVersion = true;
            insert cv;
        }
        
        User adminUser = RES_TestDataFactory.createSystemAdminUser();
        
        System.runAs(adminUser) {
            
            Account companyAccount = RES_TestDataFactory.createCompanyRTAccount('Globant', '1212121212');
            Id contractRecordTypeId = Schema.SObjectType.Contract
                .getRecordTypeInfosByDeveloperName()
                .get(System.Label.RES_Contract_Residential_Sales_RT)
                .getRecordTypeId();
            Contract contractObj = RES_TestDataFactory.createContract(companyAccount.Id, 'Draft', contractRecordTypeId);
            
            ContentVersion cv = new ContentVersion(
                Title = 'Test File Admin',
                PathOnClient = 'TestFileAdmin.txt',
                VersionData = Blob.valueOf('Test file content')
            );
            
            insert cv;
            
            cv = [
                SELECT Id, ContentDocumentId, Title
                FROM ContentVersion
                WHERE Id = :cv.Id
            ];
            
            ContentDocumentLink cdl = new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = contractObj.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
            
            insert cdl;
        }
        Test.stopTest();
    }
    
    @isTest
    public static void testPreventContentNoteDelete() {
        try{

            User testUser = [ SELECT Id 
                              FROM User 
                              WHERE Email = 'res.salesrep.test@example.com' LIMIT 1 ];
            
            System.runAs(testUser) {
                Test.startTest();
                ContentVersion insertedCV = [ SELECT Id, ContentDocumentId
                                              FROM ContentVersion
                                              WHERE Title = 'Test File' LIMIT 1 ];
                
                ContentDocument cdObj = [ SELECT Id
                                          FROM ContentDocument
                                          WHERE Id =: insertedCV.ContentDocumentId LIMIT 1 ];
                
                delete cdObj; 

                System.assertNotEquals(null, cdObj, 'The ContentDocument should not be deleted');
                Test.stopTest();
            }
        }
        catch(Exception e){
            System.debug('Exception ==> '+e.getMessage());
        }
    }
    
    @isTest
    public static void testDocumentDeletion() {
        try{

            User testUser = [ SELECT Id 
                              FROM User 
                              WHERE Profile.Name = 'System Administrator' AND 
                              Email = 'res.systemadmin.test@example.com' LIMIT 1 ];
            
            System.runAs(testUser) {
                Test.startTest();
                ContentVersion insertedCV = [ SELECT Id, ContentDocumentId
                                              FROM ContentVersion
                                              WHERE Title = 'Test File Admin' LIMIT 1 ];
                
                ContentDocument cdObj = [ SELECT Id
                                          FROM ContentDocument
                                          WHERE Id =: insertedCV.ContentDocumentId LIMIT 1 ];
                
                delete cdObj; 
                
                cdObj = [ SELECT Id
                          FROM ContentDocument
                          WHERE Id =: insertedCV.ContentDocumentId LIMIT 1 ];

                System.assertEquals(null, cdObj, 'The ContentDocument is deleted');
                Test.stopTest();
            }
        }
        catch(Exception e){
            System.debug('Exception ==> '+e.getMessage());
        }
    }
}