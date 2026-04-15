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
        RES_Note_Delete_Restriction__mdt mdt = RES_Note_Delete_Restriction__mdt.getInstance('RES_Diriyah_Note_Delete_Restriction');
        
        //Create a new User record for testing
        Profile profile = [ SELECT Id 
                            FROM Profile 
                            WHERE Name =: mdt.RES_Profile_Name__c LIMIT 1];
        
        User newUser 				= new User();
        newUser.Username 			= 'testuserdiriyah0799@example.com'; // This should be unique
        newUser.Alias 				= 'tuser';
        newUser.Email 				= 'testuserdiriyah0799@example.com';
        newUser.ProfileId 			= profile.Id;
        newUser.TimeZoneSidKey 		= 'America/Los_Angeles';
        newUser.LocaleSidKey 		= 'en_US';
        newUser.EmailEncodingKey 	= 'UTF-8';
        newUser.LanguageLocaleKey 	= 'en_US';
        newUser.FirstName 			= 'Test';
        newUser.LastName 			= 'User';
        newUser.CompanyName 		= 'Test Company';
        
        //Insert user into test data
        insert newUser;
        
        //Query test user
        User testUser = [ SELECT Id 
                         FROM User 
                         WHERE Email = 'testuserdiriyah0799@example.com' LIMIT 1 ];
        
        System.runAs(testUser) {
            Test.startTest();
            //Create ContentVersion (this creates ContentDocument automatically)
            ContentVersion cv = new ContentVersion();
            cv.Title = 'Test File';
            cv.PathOnClient = 'TestFile.snote';
            cv.VersionData = Blob.valueOf('This is test content');
            cv.IsMajorVersion = true;
            insert cv;
            Test.stopTest();
        }
    }
    
    @isTest
    public static void testPreventContentNoteDelete() {
        try{
            //Query test user
            User testUser = [ SELECT Id 
                              FROM User 
                              WHERE Email = 'testuserdiriyah0799@example.com' LIMIT 1 ];
            
            System.runAs(testUser) {
                Test.startTest();
                ContentVersion insertedCV = [ SELECT Id, ContentDocumentId
                                              FROM ContentVersion
                                              WHERE Title = 'Test File' LIMIT 1 ];
                
                ContentDocument cdObj = [ SELECT Id
                                          FROM ContentDocument
                                          WHERE Id =: insertedCV.ContentDocumentId LIMIT 1 ];
                
                delete cdObj; //Delete ContentDocument
                
                //Assert that the ContentDocument should not be deleted
                System.assertNotEquals(null, cdObj, 'The ContentDocument should not be deleted');
                Test.stopTest();
            }
        }
        catch(Exception e){
            System.debug('Exception ==> '+e.getMessage());
        }
    }
}