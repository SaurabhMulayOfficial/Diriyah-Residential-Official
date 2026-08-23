/**
 * Class Name   : RES_ProductApprovalStateService
 * Description  : Handles Product approval state transitions.
 *
 * Responsibilities:
 *      - Resolve approval configuration.
 *      - Validate transitions.
 *      - Determine next status.
 *
 * No SOQL.
 * No DML.
 */
public with sharing class RES_ProductApprovalStateService {

    /**
     * Builds:
     *
     * Current Status → Approval Configuration
     */
    public static Map<String,RES_Product_Approval_Config__mdt> buildStatusConfigMap(List<RES_Product_Approval_Config__mdt> configs) {
        Map<String,RES_Product_Approval_Config__mdt> result = new Map<String,RES_Product_Approval_Config__mdt>();
        if (configs == null) {
            return result;
        }
        for (
            RES_Product_Approval_Config__mdt config :
            configs
        ) {
            if (config == null || config.RES_Active__c != true || String.isBlank(config.RES_Current_Status__c)) {
                continue;
            }
            result.put(config.RES_Current_Status__c,config);
        }
        return result;
    }

    /**
     * Gets approval configuration for Product status.
     */
    public static RES_Product_Approval_Config__mdt getConfigForStatus(String currentStatus,Map<String,RES_Product_Approval_Config__mdt> configMap) {

        if (String.isBlank(currentStatus) || configMap == null || configMap.isEmpty()) {
            return null;
        }

        return configMap.get(currentStatus);
    }

    /**
     * Validates Product approval transition.
     */
    public static Boolean canApprove(Product2 product, RES_Product_Approval_Config__mdt config) {
        if (product == null || config == null) {
            return false;
        }
        if (String.isBlank(product.RES_Unit_Status__c)) {
            return false;
        }

        return product.RES_Unit_Status__c ==
            config.RES_Current_Status__c;
    }

    /**
     * Gets next status.
     */
    public static String getNextStatus(RES_Product_Approval_Config__mdt config) {
        if (config == null) {
            return null;
        }
        return config.RES_Next_Status__c;
    }

    /**
     * Determines whether approval is final.
     */
    public static Boolean isFinalApproval(RES_Product_Approval_Config__mdt config) {
        return (config != null &&
            config.RES_Final_Level__c == true
        );
    }

    /**
     * Valid approval rejection statuses.
     */
    public static Boolean canReject(String status) {
        return (
            status == 'Draft' ||
            status == 'Pending Finance Approval' ||
            status == 'Pending CSO Approval'
        );
    }

    /**
     * Only Rejected Products can be resubmitted.
     */
    public static Boolean canResubmit(String status) {
        return status == 'Rejected';
    }
}