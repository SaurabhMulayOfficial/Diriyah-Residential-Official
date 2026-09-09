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

    private static Boolean systemAdministrator;
    private static final RES_UserDAOLayer USER_DAO = new RES_UserDAOLayer();

    /**
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
        * Operations users can view all queues (read-only for approval tabs).
        */
        if (hasCustomPermission('RES_Product_Operation_Visibility')) {
            return true;
        }
        return canActOnConfig(config);
    }

    /**
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

    /**x
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

    /**
     *
     * @return true if current user is a System Administrator or holds the
     *         'RES_Product_Operation_Visibility' Custom Permission.
     */
    public static Boolean canSubmitForApproval() {
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