/**
 * ==============================================================================
 * Class Name    : RES_TestDataFactory (ENHANCED)
 * Description   : Centralized test data factory with all fields needed for
 *                 lead conversion tests. Includes SLA status, project fields,
 *                 and proper account/contact creation.
 *
 * Author        : Roshan Jambhule
 * Company       : Globant Inc
 * Created Date  : June 27, 2026
 * Version       : 3.0 (ENHANCED FOR LEAD CONVERSION TESTS)
 * ==============================================================================
 */
@isTest
public class RES_TestDataFactory {

    private static final String PROFILE_STANDARD    = 'Diriyah Residential Sales Standard Profile';
    private static final String PROFILE_SYSADMIN    = 'System Administrator';
    private static final String ROLE_SPECIALIST     = 'RES_Sales_DI_Specialist';
    private static final String ROLE_SR_DIRECTOR    = 'RES_Sales_DI_DII_Senior_Director';
    private static final String ROLE_EXEC_DIRECTOR  = 'RES_Sales_Operations_Executive_Director';
    private static final String PS_REL_MANAGER      = 'RES_Diriyah_Residential_DI_Specialist_Permission_Set';
    private static final String PS_DIRECTOR         = 'RES_Diriyah_Residential_Wadi_Safar_Senior_Director_Permission_Set';
    private static final String PS_MANAGER          = 'RES_Diriyah_Residential_Wadi_Safar_Senior_Manager_Permission_Set';
    private static final String LEAD_RECORD_TYPE    = 'Residential Company';
    private static final String PROJECT_DEFAULT     = 'Amansamar Residences Wadi Safar';

    private class UserConfig {
        String email;
        String username;
        String firstName;
        String lastName;
        String alias;
        String profileName;
        String roleDeveloperName;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // User Creation Methods
    // ═══════════════════════════════════════════════════════════════════════

    public static User createSalesRepUser() {
        UserConfig config = new UserConfig();
        config.email             = 'res.salesrep.test@example.com';
        config.username          = 'res.salesrep.test@example.com.sandbox';
        config.firstName         = 'Sales';
        config.lastName          = 'Rep';
        config.alias             = 'srep';
        config.profileName       = PROFILE_STANDARD;
        config.roleDeveloperName = ROLE_SPECIALIST;
        User u = buildUser(config);
        insert u;
        assignPermissionSet(u.Id, PS_REL_MANAGER);
        return u;
    }

    public static User createSalesDirectorUser() {
        UserConfig config = new UserConfig();
        config.email             = 'res.salesdirector.test@example.com';
        config.username          = 'res.salesdirector.test@example.com.sandbox';
        config.firstName         = 'Sales';
        config.lastName          = 'Director';
        config.alias             = 'sdir';
        config.profileName       = PROFILE_STANDARD;
        config.roleDeveloperName = ROLE_SR_DIRECTOR;
        User u = buildUser(config);
        insert u;
        assignPermissionSet(u.Id, PS_DIRECTOR);
        return u;
    }

    public static User createSalesManagerUser() {
        UserConfig config = new UserConfig();
        config.email             = 'res.salesmanager.test@example.com';
        config.username          = 'res.salesmanager.test@example.com.sandbox';
        config.firstName         = 'Sales';
        config.lastName          = 'Manager';
        config.alias             = 'smgr';
        config.profileName       = PROFILE_SYSADMIN;
        config.roleDeveloperName = ROLE_EXEC_DIRECTOR;
        User u = buildUser(config);
        insert u;
        assignPermissionSet(u.Id, PS_MANAGER);
        return u;
    }

    public static User createSystemAdminUser() {
        Profile prof = [
            SELECT Id FROM Profile
            WHERE Name = :PROFILE_SYSADMIN
            LIMIT 1
        ];

        User u = new User(
            Alias             = 'sadmin',
            Email             = 'res.systemadmin.test@example.com',
            EmailEncodingKey  = 'UTF-8',
            FirstName         = 'System',
            LastName          = 'Admin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            ProfileId         = prof.Id,
            TimeZoneSidKey    = 'Asia/Kolkata',
            Username          = 'res.systemadmin.test@example.com.sandbox'
        );

        insert u;
        return u;
    }

    /**
     * @description Creates and inserts a bare user for a given Profile, with
     *              no Role and no Permission Set assignment, and a
     *              randomized alias/email/username so it can be called
     *              multiple times per test method without colliding (unlike
     *              createSystemAdminUser(), which uses a single fixed
     *              username). Intended for test classes outside the
     *              Lead-conversion domain (e.g. Product Approval) that only
     *              need to pin down the Profile (for System-Administrator
     *              bypass checks) and/or exercise "no Custom Permission
     *              assigned" negative paths, without depending on any
     *              Sales-specific Role/PermissionSet existing in the org.
     * @param profileName Exact Profile Name to assign (e.g.
     *                    'System Administrator', 'Standard User').
     * @return Inserted User record.
     */
    public static User createGenericUser(String profileName) {
        Profile prof = [
            SELECT Id FROM Profile
            WHERE Name = :profileName
            LIMIT 1
        ];
        String uniqueSuffix = String.valueOf(Crypto.getRandomInteger()).right(5);
        User u = new User(
            Alias             = 'gu' + uniqueSuffix.left(4),
            Email             = 'res.genericuser.' + uniqueSuffix + '@example.com',
            EmailEncodingKey  = 'UTF-8',
            FirstName         = 'Generic',
            LastName          = 'User' + uniqueSuffix,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            ProfileId         = prof.Id,
            TimeZoneSidKey    = 'Asia/Kolkata',
            Username          = 'res.genericuser.' + uniqueSuffix + '@example.com.sandbox'
        );
        insert u;
        return u;
    }

    /**
     * @description Public entry point to assign an arbitrary named
     *              Permission Set to an arbitrary user. Thin wrapper around
     *              the private assignPermissionSet() so other domains (e.g.
     *              Product Approval, if a Permission Set granting its
     *              Custom Permission needs to be assigned in a future
     *              positive-path test) can reuse the same lookup/assign
     *              logic without duplicating it.
     * @param userId Id of the user to assign the Permission Set to.
     * @param psName Name of the Permission Set to assign.
     */
    public static void assignPermissionSetToUser(Id userId, String psName) {
        assignPermissionSet(userId, psName);
    }

    private static User buildUser(UserConfig config) {
        Profile prof = [
            SELECT Id FROM Profile
            WHERE Name = :config.profileName
            LIMIT 1
        ];
        UserRole role = [
            SELECT Id FROM UserRole
            WHERE DeveloperName = :config.roleDeveloperName
            LIMIT 1
        ];
        return new User(
            Alias             = config.alias,
            Email             = config.email,
            EmailEncodingKey  = 'UTF-8',
            FirstName         = config.firstName,
            LastName          = config.lastName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            ProfileId         = prof.Id,
            TimeZoneSidKey    = 'Asia/Kolkata',
            Username          = config.username,
            UserRoleId        = role.Id
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Lead Creation Methods (ENHANCED FOR CONVERSION TESTS)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Creates a basic test lead
     * @param email Lead email address
     * @return Lead with auto-generated phone from email hash
     */
    public static Lead createLead(String email) {
        return createLeadWithProject(email, PROJECT_DEFAULT);
    }

    /**
     * @description Creates a test lead with custom project
     * @param email Lead email address
     * @param project RES_Project__c value
     * @return Lead with all required fields for conversion
     */
    public static Lead createLeadWithProject(String email, String project) {
        return createLeadFull(email, null, null, project, null, 'Met');
    }

    /**
     * @description Creates a test lead with SLA status and project
     * @param email Lead email address
     * @param slaStatus RES_SLA_Status__c value
     * @param project RES_Project__c value
     * @return Lead ready for conversion testing
     */
    public static Lead createLeadWithSLA(String email, String slaStatus, String project) {
        return createLeadFull(email, null, null, project, null, slaStatus);
    }

    /**
     * @description Creates a lead with all possible parameters
     * @param email Lead email
     * @param mobilePhone Lead mobile phone (auto-generated if null)
     * @param company Lead company
     * @param project RES_Project__c
     * @param status Lead status
     * @param slaStatus RES_SLA_Status__c
     * @return Lead with all fields populated
     */
    public static Lead createLeadFull(
        String email,
        String mobilePhone,
        String company,
        String project,
        String status,
        String slaStatus
    ) {
        RecordType rt = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Lead'
            AND Name = :LEAD_RECORD_TYPE
            LIMIT 1
        ];
    
        String prefix = email.substringBefore('@').left(10);
        String hashStr = String.valueOf(Math.abs(email.hashCode()));
        String uniquePhone = mobilePhone != null ? mobilePhone : '+9198' + hashStr.left(7).rightPad(7, '0');
    
        Lead l = new Lead(
            OwnerId = UserInfo.getUserId(),
            RecordTypeId = rt.Id,
            FirstName = prefix,
            LastName = 'TestLead',
            Company = company != null ? company : prefix + ' Co',
            Status = status != null ? status : 'New',
            Email = email,
            Phone = uniquePhone,
            MobilePhone = uniquePhone,
            RES_Project__c = project != null ? project : PROJECT_DEFAULT,
            RES_SLA_Status__c = slaStatus != null ? slaStatus : 'Running'
        );
    
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.duplicateRuleHeader.allowSave = true;
    
        Database.SaveResult sr = Database.insert(l, dml);
    
        if(sr.isSuccess()){
            l.Id = sr.getId();
        }
    
        return l;
    }

    /**
     * @description Creates a lead for individual record type
     * @param email Lead email
     * @param source Lead source
     * @param ownerId Lead owner ID
     * @return Lead with specified owner and source
     */
    public static Lead createLead(String email, String source, Id ownerId) {
        Id rtId_individual = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
            .get('RES_Individual')
            .getRecordTypeId();
        
        String prefix = email.substringBefore('@').left(10);
        String hashStr = String.valueOf(Math.abs(email.hashCode()));
        String uniquePhone = '+9198' + hashStr.left(7).rightPad(7, '0');
        
        Lead l = new Lead(
            OwnerId = ownerId,
            RecordTypeId = rtId_individual,
            FirstName = prefix,
            LastName = 'TestLead',
            Company = prefix + ' Co',
            Status = 'New',
            Email = email,
            Phone = uniquePhone,
            MobilePhone = uniquePhone,
            LeadSource = source,
            RES_Project__c = PROJECT_DEFAULT,
            RES_SLA_Status__c = 'Met'
        );

        insert l;
        return l;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Account Creation Methods (ENHANCED)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Creates a test account with default values
     * @return Account ready for linking in conversion tests
     */
    public static Account createAccount() {
        String uniqueCRNumber = '8624' + String.valueOf(System.currentTimeMillis()).right(6);
        return createAccountFull('Test Account', uniqueCRNumber, 'ZIT04');
    }

    /**
     * @description Creates a test account with custom values
     * @param name Account name
     * @return Account
     */
    public static Account createAccountWithName(String name) {
        String uniqueCRNumber = '8624' + String.valueOf(System.currentTimeMillis()).right(6);
        return createAccountFull(name, uniqueCRNumber, 'ZIT04');
    }

    /**
     * @description Creates a test account with all fields
     * @param name Account name
     * @param crNumber RES_CR_number__c
     * @param idType RES_Identification_Type__c
     * @return Account with all fields
     */
    public static Account createAccountFull(String name, String crNumber, String idType) {
        Account acc = new Account(
            Name = name,
            RES_CR_number__c = crNumber != null ? crNumber : '8624' + String.valueOf(System.currentTimeMillis()).right(6),
            RES_Identification_Type__c = idType
        );
        insert acc;
        return acc;
    }
    
    /**
     * @description Creates a Company Record Type test account with all fields
     * @param name Account name
     * @return Account with all fields
     */
    public static Account createCompanyRTAccount(String name, String crNumber) {
        Id recordTypeId = Schema.SObjectType.Account
                         .getRecordTypeInfosByDeveloperName()
                         .get('RES_Company')
                         .getRecordTypeId();
        
        Account acc = new Account(
            Name = name,
            RecordTypeId = recordTypeId,
            BillingCountry = 'India',
            BillingStreet = 'Pune',
            BillingPostalCode = '411014',
            BillingCity = 'Pune',
            RES_CR_number__c = crNumber, 
            RES_Identification_Type__c = 'ZIT04'
        );
        insert acc;
        return acc;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Contact Creation Methods (ENHANCED)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Creates a test contact
     * @param accountId Contact's account
     * @param email Contact email
     * @param mobilePhone Contact mobile phone
     * @return Contact
     */
    public static Contact createContact(Id accountId, String email, String mobilePhone) {
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = email,
            MobilePhone = mobilePhone,
            AccountId = accountId
        );
        insert con;
        return con;
    }

    /**
     * @description Creates a test contact with custom name
     * @param accountId Contact's account
     * @param firstName Contact first name
     * @param lastName Contact last name
     * @param mobilePhone Contact mobile phone
     * @return Contact
     */
    public static Contact createContactFull(
        Id accountId,
        String firstName,
        String lastName,
        String mobilePhone
    ) {
        Contact con = new Contact(
            FirstName = firstName,
            LastName = lastName,
            MobilePhone = mobilePhone,
            AccountId = accountId
        );
        insert con;
        return con;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Utility Methods
    // ═══════════════════════════════════════════════════════════════════════

    public static RES_LeadMassConversionUtility.ConvertRequest buildRequest(
        List<Lead> leads,
        String statusLabel,
        Boolean doNotCreateOpp
    ) {
        RES_LeadMassConversionUtility.ConvertRequest req =
            new RES_LeadMassConversionUtility.ConvertRequest();
        req.leads = leads;
        req.convertedStatusLabel = statusLabel;
        req.doNotCreateOpp = doNotCreateOpp;
        return req;
    }

    public static String getConvertedStatus() {
        return [
            SELECT MasterLabel FROM LeadStatus
            WHERE IsConverted = true
            AND MasterLabel = 'Converted'
            LIMIT 1
        ].MasterLabel;
    }

    private static void assignPermissionSet(Id userId, String psName) {
        PermissionSet ps = [
            SELECT Id FROM PermissionSet
            WHERE Name = :psName
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = ps.Id
        );
    }

    public static ContentVersion createFile() {
        ContentVersion cv = new ContentVersion();
        cv.Title = 'TestFile';
        cv.PathOnClient = 'TestFile.pdf';
        cv.VersionData = Blob.valueOf('Test File Content');
        insert cv;
        return [
            SELECT Id, Title, ContentDocumentId, RES_Document_Label__c
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
    }
    
    public static ContentVersion createContentVersionWithAttachmentType(String attachmentType) {
        ContentVersion cv = new ContentVersion();
        cv.Title = 'TestFile';
        cv.PathOnClient = 'TestFile.pdf';
        cv.VersionData = Blob.valueOf('Test File Content');
        cv.RES_Attachment_Type__c = attachmentType;
        insert cv;
        return [
            SELECT Id, Title, ContentDocumentId, RES_Document_Label__c
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
    }

    public static ContentDocumentLink createDocLink(String accId, String cdId) {
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = cdId;
        cdl.LinkedEntityId = accId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        insert cdl;
        return cdl;
    }
    
    public static ContentDocumentLink createDocLinkForContract(String contractId, String cdId) {
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = cdId;
        cdl.LinkedEntityId = contractId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        insert cdl;
        return cdl;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Opportunity Creation Methods
    // ═══════════════════════════════════════════════════════════════════════
	/**
     * @description Creates a test contact
     * @param name - Opportunity Name
     * @param accountId - Account Record Id
     * @param stage - Opportunity Stage
     * @param closeDate - Opportunity Close Date
     * @param project - Opportunity Project
     * @return Opportunity
     */
    public static Opportunity createSingleBuyerOpportunity(String name, Id accountId, String stage, Date closeDate, String project) {
        Id recordTypeId = Schema.SObjectType.Opportunity
    					.getRecordTypeInfosByDeveloperName()
    					.get('RES_Residential_Single_Buyer')
    					.getRecordTypeId();

        Opportunity opp = new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = stage, 
            CloseDate = closeDate, 
            RES_Project__c  = project,
            RecordTypeId = recordTypeId
        );
        insert opp;
        return opp;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Quote Creation Methods
    // ═══════════════════════════════════════════════════════════════════════
	/**
     * @description Creates a test Quote
     * @param name - Quote Name
     * @param opportunityId - opportunity Record Id
     * @param priceBookId - priceBookId
     * @param status - quote status
     * @return Quote
     */
    public static Quote createQuote(String name, Id opportunityId, Id priceBookId, String status, Id quoteRecordTypeId) {
        Quote quoteObj = new Quote(
            Name = name,
            OpportunityId = opportunityId,
            Pricebook2Id = priceBookId,
            Status = status,
            RecordTypeId = quoteRecordTypeId
        );
        insert quoteObj;
        return quoteObj;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Quote Line Item Creation Methods
    // ═══════════════════════════════════════════════════════════════════════
	/**
     * @description Creates a test Quote Line Item
     * @param quoteId - quoteId
     * @param quantity - quantity
     * @param unitPrice - unitPrice
     * @return QuoteLineItem
     */
    public static QuoteLineItem createQuoteLineItem(Id quoteId, Integer quantity, Integer unitPrice) {
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = quoteId,
            PricebookEntryId = createPricebookEntry().Id,
            Quantity = quantity,
            UnitPrice = unitPrice
        );
        insert qli;
        return qli;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Product Creation Methods
    // ═══════════════════════════════════════════════════════════════════════
	/**
     * @description Creates a test Product
     * @param name - name
     * @return Product2
     */
    public static Product2 createProduct(String name) {
        Product2 prod = new Product2(
            Name = name,
            IsActive = true
        );
        insert prod;
        return prod;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Product Creation Methods
    // ═══════════════════════════════════════════════════════════════════════
	/**
     * @description Creates a test PricebookEntry
     * @param 
     * @return PricebookEntry
     */
    public static PricebookEntry createPricebookEntry() {
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = createProduct('Mobile').Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;
        return pbe;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Contract Creation Methods
    // ═══════════════════════════════════════════════════════════════════════
	/**
     * @description Creates a test Contract
     * @param accountId - accountId
     * @param status - status
     * @param recordTypeId - recordTypeId
     * @return Contract
     */
    public static Contract createContract(Id accountId, String status, Id recordTypeId) {
        Contract con = new Contract(
            AccountId = accountId,
            Status = status,
            RecordTypeId = recordTypeId
        );
        insert con;
        return con;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Group Creation Methods
    // ═══════════════════════════════════════════════════════════════════════
	/**
     * @description Creates a test Group
     * @param name - name
     * @return Group
     */
    public static Group createGroup(String name) {
        Group testGroup = new Group(
            Name = name,
            Type = 'Regular'
        );
        insert testGroup;
        return testGroup;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Group Member Creation Methods
    // ═══════════════════════════════════════════════════════════════════════
	/**
     * @description Creates a test Group Member
     * @param groupId - groupId
     * @param userId - userId
     * @return Group Member
     */
    public static List<GroupMember> createGroupMembers(Id groupId, Id userId) {
        List<GroupMember> members = new List<GroupMember>{
            new GroupMember(
                GroupId = groupId,
                UserOrGroupId = userId
            )
        };

        insert members;
        return members;
    }
}