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
 * Created Date  : Mar 2, 2026
 * Version       : 2.0
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
    private static final String PS_MANAGER          = 'Diriyah_Sales_Manager_Permission_Set';
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

    // ═════════════════════════════════════════════════════════════════
    // LEAD FACTORY METHOD
    // ═════════════════════════════════════════════════════════════════
    /**
     * Creates and inserts a single Lead using DMLOptions to bypass
     * duplicate rules — mirrors the verified Anonymous Apex pattern.
     *
     * Uniqueness strategy — every duplicate-sensitive field is derived
     * from the email so no two test leads share identical values:
     *   • FirstName / Company               → email prefix (left 10 chars)
     *   • MobilePhone / Phone               → '+9198' + 7-digit hash
     *   • RES_Identification_Number__c      → full hash (unique field)
     *
     * @param  email  Unique email — drives all unique field values
     * @return        Inserted Lead record
     */
    public static Lead createLead(String email) {
        RecordType rt = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Lead'
            AND   Name        = :LEAD_RECORD_TYPE
            LIMIT 1
        ];

        String prefix      = email.substringBefore('@').left(10);
        String hashStr     = String.valueOf(Math.abs(email.hashCode()));
        String uniquePhone = '+9198' + hashStr.left(7).rightPad(7, '0');

        Lead l = new Lead(
            // ── Standard Fields ───────────────────────────────────────
            OwnerId                       = UserInfo.getUserId(),
            RecordTypeId                  = rt.Id,
            Salutation                    = 'Mr.',
            FirstName                     = prefix,
            LastName                      = 'TestLead',
            Status                        = 'New',            
            Email                         = email,
            Phone                         = uniquePhone,
            MobilePhone                   = uniquePhone,
            Company                       = prefix + ' Co',
            State                         = 'Abu Dhabi',
            LeadSource                    = 'Employee_Referral',
            GenderIdentity                = 'GTM',               
            // ── Custom Fields ─────────────────────────────────────────
            RES_Nationality__c            = 'Indian',
            RES_BP_Role__c                = 'ZTR601',
            RES_Customer_Interest__c      = '101',
            RES_Identification_Number__c  = hashStr,
            RES_Identification_Type__c    = 'ZIT01',
            RES_Lead_Type__c              = 'LT02'
        );

        // ✅ allowSave = true bypasses org duplicate rules in test context
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.duplicateRuleHeader.allowSave = true;
        Database.insert(l, dml);

        return l;
    }

    // ═════════════════════════════════════════════════════════════════
    // CONVERT REQUEST HELPERS
    // ═════════════════════════════════════════════════════════════════

    /**
     * Builds a ConvertRequest wrapper for the invocable method.
     *
     * @param  leads          List of Lead records to include
     * @param  statusLabel    MasterLabel of the target LeadStatus
     * @param  doNotCreateOpp true = skip Opportunity creation
     * @return                Populated ConvertRequest
     */
    public static RES_LeadMassConversionUtility.ConvertRequest buildRequest(
        List<Lead>  leads,
        String      statusLabel,
        Boolean     doNotCreateOpp
    ) {
        RES_LeadMassConversionUtility.ConvertRequest req =
            new RES_LeadMassConversionUtility.ConvertRequest();
        req.leads                = leads;
        req.convertedStatusLabel = statusLabel;
        req.doNotCreateOpp       = doNotCreateOpp;
        return req;
    }

    /**
     * Fetches the MasterLabel of the first converted LeadStatus in org.
     *
     * @return MasterLabel string of a converted LeadStatus
     */
    public static String getConvertedStatus() {
        return [
            SELECT MasterLabel FROM LeadStatus
            WHERE IsConverted = true
            AND   MasterLabel = 'Qualified'
            LIMIT 1
        ].MasterLabel; // ✅ 'Qualified' → DAO returns 'Qualified' → Database.convertLead() accepts it
    }

    /**
     * Assigns a named PermissionSet to a User.
     */
    private static void assignPermissionSet(Id userId, String psName) {
        PermissionSet ps = [
            SELECT Id FROM PermissionSet
            WHERE Name = :psName
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId      = userId,
            PermissionSetId = ps.Id
        );
    }
}