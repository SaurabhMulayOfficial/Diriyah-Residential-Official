/**
 * ==============================================================================
 * Class Name    : RES_TestDataFactory
 * Description   : Centralized test data factory for RES_LeadMassConversionUtility
 *                 tests. Provides reusable methods to create Users, Leads, and
 *                 ConvertRequests so test classes stay lean and maintainable.
 *                 createSalesRepUser()       Diriyah Standard Profile
 *                                            RES_Sales_DI_Specialist role
 *                                            RES_Diriyah_Sales_Relationship_Manager_Permission_Set
 *                 createSalesDirectorUser()  Diriyah Standard Profile
 *                                            RES_Sales_DI_DII_Senior_Director role
 *                                            RES_Diriyah_Sales_Director_Permission_Set
 *                 createSalesManagerUser()   System Administrator Profile
 *                                            RES_Sales_Operations_Executive_Director role
 *                                            RES_Diriyah_Sales_Manager_Permission_Set
 *                 createLead(email)          Single Lead, all dupe-sensitive
 *                                            fields derived from email hash
 *                 buildRequest(...)          Builds a ConvertRequest wrapper
 *                 getConvertedStatus()       Fetches first IsConverted LeadStatus
 * Author        : Rohan Jambhule
 * Company       : Globant Inc
 * Created Date  : Mar 2, 2026s
 * Version       : 1.0
 * ==============================================================================
 */
@isTest
public class RES_TestDataFactory {

    // ─────────────────────────────────────────────────────────────────
    // Constants — single place to update if org config changes
    // ─────────────────────────────────────────────────────────────────
    private static final String PROFILE_STANDARD    = 'Diriyah Residential Sales Standard Profile';
    private static final String PROFILE_SYSADMIN    = 'System Administrator';
    private static final String ROLE_SPECIALIST     = 'RES_Sales_DI_Specialist';
    private static final String ROLE_SR_DIRECTOR    = 'RES_Sales_DI_DII_Senior_Director';
    private static final String ROLE_EXEC_DIRECTOR  = 'RES_Sales_Operations_Executive_Director';
    private static final String PS_REL_MANAGER      = 'RES_Diriyah_Sales_Relationship_Manager_Permission_Set';
    private static final String PS_DIRECTOR         = 'RES_Diriyah_Sales_Director_Permission_Set';
    private static final String PS_MANAGER          = 'RES_Diriyah_Sales_Manager_Permission_Set';
    private static final String LEAD_RECORD_TYPE    = 'Residential Company';

    // ═════════════════════════════════════════════════════════════════
    // USER FACTORY METHODS
    // ═════════════════════════════════════════════════════════════════
    private class UserConfig {
        String email;
        String username;
        String firstName;
        String lastName;
        String alias;
        String profileName;
        String roleDeveloperName;
    }

    /**
     * Creates and inserts a Sales Rep user.
     * Profile  : Diriyah Residential Sales Standard Profile
     * Role     : RES_Sales_DI_Specialist
     * Perm Set : RES_Diriyah_Sales_Relationship_Manager_Permission_Set
     */
    public static User createSalesRepUser() {
        UserConfig config = new UserConfig();
        config.email = 'res.salesrep.test@example.com';
        config.username = 'res.salesrep.test@example.com.sandbox';
        config.firstName = 'Sales';
        config.lastName = 'Rep';
        config.alias = 'srep';
        config.profileName = PROFILE_STANDARD;
        config.roleDeveloperName = ROLE_SPECIALIST;
        User u = buildUser(config);
        insert u;
        assignPermissionSet(u.Id, PS_REL_MANAGER);
        return u;
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

    // =========================================================================
    // Creates a valid Lead for conversion testing.
    // RecordType must match DAO filter (RES_Company or RES_Individual).
    // All required fields for conversion populated.
    // =========================================================================
    public static Lead createLead(String email) {
        Id rtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Lead'
            AND DeveloperName = 'RES_Company'
            LIMIT 1
        ].Id;
    
        String prefix  = email.substringBefore('@').left(8);
        String hashStr = String.valueOf(Math.abs(email.hashCode()));
    
        Lead l = new Lead(
            FirstName                    = prefix,
            LastName                     = 'TestLead',
            Status                       = 'Qualified',
            Email                        = email,
            Phone                        = '+9198' + hashStr.left(7).rightPad(7, '0'),
            MobilePhone                  = '+9191' + hashStr.left(7).rightPad(7, '0'),
            Company                      = prefix + ' Corp ' + hashStr.left(4),
            State                        = 'Abu Dhabi',
            LeadSource                   = 'Employee_Referral',
            Salutation                   = 'Mr.',
            GenderIdentity               = 'GTM',
            RecordTypeId                 = rtId,
            OwnerId                      = UserInfo.getUserId(), // ✅ Explicitly set running user
            RES_Nationality__c           = 'Indian',
            RES_BP_Role__c               = 'ZTR601',
            RES_Customer_Interest__c     = '101',
            RES_Identification_Number__c = hashStr.left(10),
            RES_Identification_Type__c   = 'ZIT01',
            RES_Lead_Type__c             = 'LT02'
        );
        insert l;
        return l;
    }

     // =========================================================================
    // Builds a ConvertRequest wrapper for use in test methods.
    // statusLabel should be MasterLabel (e.g. 'Qualified') —
    // DAO will convert it to ApiName ('04') internally.
    // =========================================================================
    public static RES_LeadMassConversionUtility.ConvertRequest buildRequest(
        List<Lead> leads,
        String statusLabel,
        Boolean doNotCreateOpp
    ) {
        RES_LeadMassConversionUtility.ConvertRequest req =
            new RES_LeadMassConversionUtility.ConvertRequest();
        req.leads                = leads;
        req.convertedStatusLabel = statusLabel;
        req.doNotCreateOpp       = doNotCreateOpp;
        return req;
    }

    // =========================================================================
    // Returns the MasterLabel of the converted LeadStatus.
    // Passes MasterLabel to buildRequest — DAO will return ApiName ('04').
    // =========================================================================
    public static String getConvertedStatus() {
        LeadStatus ls = [
            SELECT MasterLabel, ApiName
            FROM LeadStatus
            WHERE IsConverted = true
            AND MasterLabel = 'Qualified'   // ✅ Matches leads created in createLead()
            LIMIT 1
        ];
        return ls.MasterLabel;             // ✅ Returns 'Qualified' → DAO converts to '04'
    }


    /**
     * Assigns a named PermissionSet to a User.
     */
    private static void assignPermissionSet(Id userId, String psName) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
        insert new PermissionSetAssignment(
            AssigneeId      = userId,
            PermissionSetId = ps.Id
        );
    }

    public static User createSalesDirectorUser() {
        UserConfig config = new UserConfig();
        config.email = 'res.salesdirector.test@example.com';
        config.username = 'res.salesdirector.test@example.com.sandbox';
        config.firstName = 'Sales';
        config.lastName = 'Director';
        config.alias = 'sdir';
        config.profileName = PROFILE_STANDARD;
        config.roleDeveloperName = ROLE_SR_DIRECTOR;
    
        User u = buildUser(config);
        insert u;
        assignPermissionSet(u.Id, PS_DIRECTOR);
        return u;
    }

    public static User createSalesManagerUser() {
        UserConfig config = new UserConfig();
        config.email = 'res.salesmanager.test@example.com';
        config.username = 'res.salesmanager.test@example.com.sandbox';
        config.firstName = 'Sales';
        config.lastName = 'Manager';
        config.alias = 'smgr';
        config.profileName = PROFILE_SYSADMIN;
        config.roleDeveloperName = ROLE_EXEC_DIRECTOR;
    
        User u = buildUser(config);
        insert u;
        assignPermissionSet(u.Id, PS_MANAGER);
        return u;
    }
}