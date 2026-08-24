/**
 * ==============================================================================
 * Class Name    : RES_ProductApprovalAuthorization
 * Description   : Handles authorization for Product approval actions.
 *
 * Responsibilities:
 *      - Determine user's approval permissions.
 *      - Determine accessible approval levels.
 *      - Determine whether user can approve/reject a given level.
 *
 * This class does NOT perform DML and does NOT perform SOQL directly
 * (User profile lookups are delegated to RES_UserDAOLayer).
 * ==============================================================================
 */
public with sharing class RES_ProductApprovalAuthorization {

    /*
     * Cached System Administrator flag.
     * Prevents repeated User queries within the same transaction.
     * NOTE: this is a per-transaction (static) cache. Each test method
     * runs in its own transaction, so it does not leak between tests.
     */
    private static Boolean systemAdministrator;
    /*
     * User DAO dependency.
     * All User data access must go through the DAO layer.
     */
    private static final RES_UserDAOLayer USER_DAO = new RES_UserDAOLayer();

    /**
     * Checks whether current user has a Custom Permission.
     * Custom Permission DeveloperName is supplied by CMDT.
     * @param customPermissionDeveloperName
     *        Custom Permission DeveloperName.
     * @return true if current user has the permission; false if the
     *         permission name is blank, unknown, misconfigured, or if
     *         FeatureManagement throws for any other reason (fail-closed).
     */
    public static Boolean hasCustomPermission(String customPermissionDeveloperName) {
        if (String.isBlank(customPermissionDeveloperName)) {
            return false;
        }
        try {
            return FeatureManagement.checkPermission(customPermissionDeveloperName);
        } catch (Exception ex) {
            /*
             * Invalid/misconfigured Custom Permission
             * should never grant access.
             */
            return false;
        }
    }

    /**
     * Determines whether current user can act on a
     * particular approval configuration.
     * @param config Approval configuration.
     * @return true only if config is non-null, active, has a configured
     *         Custom Permission DeveloperName, and the current user holds
     *         that Custom Permission.
     */
    public static Boolean canActOnConfig(RES_Product_Approval_Config__mdt config) {
        if (
            config == null ||
            config.RES_Active__c != true ||
            String.isBlank(config.RES_Custom_Permission__c)
        ) {
            return false;
        }
        return hasCustomPermission(
            config.RES_Custom_Permission__c
        );
    }

    /**
     * Determines whether current user is a
     * System Administrator.
     * The result is cached for the current transaction
     * to avoid repeated User queries.
     * System Administrator receives full access to
     * Product Approval queues and actions.
     *
     * @return true if current user's Profile.Name is exactly
     *         'System Administrator'; false if the user/profile cannot be
     *         resolved (fail-closed) or the profile name differs.
     */
    private static Boolean isSystemAdministrator() {
        if (systemAdministrator != null) {
            return systemAdministrator;
        }

        systemAdministrator = false;
        List<User> users = USER_DAO.getUserProfileInfo(UserInfo.getUserId());
        if (
            users == null ||
            users.isEmpty() ||
            users[0].Profile == null
        ) {
            return systemAdministrator;
        }

        systemAdministrator = users[0].Profile.Name == 'System Administrator';
        return systemAdministrator;
    }

    /**
     * Determines whether current user can view a queue.
     *
     * Rules:
     *      1. System Administrator can view all queues.
     *      2. Other users can view only the queue for which
     *         they have the configured Custom Permission.
     *
     * @param config Approval configuration.
     * @return true if current user can view the queue; false if config is
     *         null and the user is not a System Administrator.
     */
    public static Boolean canViewConfig(RES_Product_Approval_Config__mdt config) {
        if (config == null) {
            return false;
        }
        /*
        * System Administrator has full visibility.
        */
        if (isSystemAdministrator()) {
            return true;
        }
        /*
        * Non-admin users can view only the
        * approval queue for which they have
        * the configured Custom Permission.
        */
    return canActOnConfig(config);
}

    /**
     * Determines whether current user can approve.
     *
     * System Administrator has full approval authority.
     * Other users require the Custom Permission configured
     * for the respective approval stage.
     *
     * @param config Approval configuration.
     * @return true if current user can approve; false if config is null
     *         and the user is not a System Administrator.
     */
    public static Boolean canApprove(RES_Product_Approval_Config__mdt config) {
        if (config == null) {
            return false;
        }

        /*
         * System Administrator can approve
         * at any approval stage.
         */
        if (isSystemAdministrator()) {
            return true;
        }
        return canActOnConfig(config);
    }

    /**
     * Determines whether current user can reject.
     *
     * System Administrator has full rejection authority.
     * Other users require the Custom Permission configured
     * for the respective approval stage.
     *
     * @param config Approval configuration.
     * @return true if current user can reject; false if config is null
     *         and the user is not a System Administrator.
     */
    public static Boolean canReject(RES_Product_Approval_Config__mdt config) {
        if (config == null) {
            return false;
        }
        /*
         * System Administrator can reject
         * at any approval stage.
         */
        if (isSystemAdministrator()) {
            return true;
        }
        return canActOnConfig(config);
    }

    /**
     * Determines whether current user can resubmit
     * a rejected Product.
     *
     * System Administrator has full access.
     * Other users require Operations Custom Permission
     * ('RES_Product_Operation_Visibility').
     *
     * @return true if current user is a System Administrator or holds the
     *         'RES_Product_Operation_Visibility' Custom Permission.
     */
    public static Boolean canResubmit() {
        /*
        * System Administrator has full approval
        * administration access.
        */
        if (isSystemAdministrator()) {
            return true;
        }
        return hasCustomPermission(
            'RES_Product_Operation_Visibility'
        );
    }
}