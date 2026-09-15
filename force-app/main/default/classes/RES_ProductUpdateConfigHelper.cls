/**
 * Class Name   : RES_ProductUpdateConfigHelper
 * Description  : Helper class for retrieving Product Update Modal configuration
 *                from Custom Metadata and Custom Labels. Makes the LWC
 *                configuration-driven instead of hardcoded.
 *
 * Usage:
 *      RES_ProductUpdateConfigHelper.getConfigForStatus('Active');
 *      RES_ProductUpdateConfigHelper.getLabel('RES_Product_Update_Warning_Active');
 */
public without sharing class RES_ProductUpdateConfigHelper {

    /**
     * DAO instance for accessing Product Update Config metadata
     */
    private static RES_ProductUpdateConfigDAO dao = new RES_ProductUpdateConfigDAO();

    /**
     * Retrieves all active Product Update configurations
     * @return Map of Status Value => Configuration Record
     * @throws AuraHandledException if configuration retrieval fails
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, ProductUpdateConfig> getAllConfigs() {
        try {
            Map<String, ProductUpdateConfig> result = new Map<String, ProductUpdateConfig>();

            // Query all active configs using DAO layer
            List<RES_Product_Update_Config__mdt> configs = dao.getActiveConfigs();

            // Null check - return empty map if no configs found
            if (configs == null || configs.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'No active Product Update configurations found');
                return result;
            }

            // Convert to wrapper class for LWC consumption
            // Bulkified processing - handles all configs in one loop
            for (RES_Product_Update_Config__mdt config : configs) {
                // Null check for critical fields
                if (String.isBlank(config.RES_Status_Value__c)) {
                    System.debug(LoggingLevel.WARN, 'Skipping config with blank Status Value: ' + config.DeveloperName);
                    continue;
                }

                ProductUpdateConfig wrapper = new ProductUpdateConfig();
                wrapper.statusValue = config.RES_Status_Value__c;
                wrapper.warningLabelName = config.RES_Warning_Label__c;
                wrapper.requiresWarning = config.RES_Requires_Warning__c != null
                    ? config.RES_Requires_Warning__c
                    : false;
                wrapper.targetStatus = config.RES_Target_Status__c;
                wrapper.minCommentLength = config.RES_Min_Comment_Length__c != null
                    ? config.RES_Min_Comment_Length__c.intValue()
                    : 10; // Default minimum

                // Get the actual label value
                wrapper.warningMessage = getLabel(config.RES_Warning_Label__c);

                result.put(config.RES_Status_Value__c, wrapper);
            }

            return result;

        } catch (Exception e) {
            // Log the error for debugging
            System.debug(LoggingLevel.ERROR, 'Error retrieving Product Update configs: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());

            // Throw AuraHandledException for LWC to handle
            throw new AuraHandledException('Unable to load configuration: ' + e.getMessage());
        }
    }

    /**
     * Retrieves configuration for a specific status
     * @param statusValue The product status (e.g., 'Active', 'Soft Hold')
     * @return Configuration wrapper or null if not found
     * @throws AuraHandledException if configuration retrieval fails
     */
    @AuraEnabled(cacheable=true)
    public static ProductUpdateConfig getConfigForStatus(String statusValue) {
        try {
            // Validate input parameter
            if (String.isBlank(statusValue)) {
                System.debug(LoggingLevel.WARN, 'getConfigForStatus called with blank statusValue');
                return null;
            }

            // Get all configs (cached by DAO)
            Map<String, ProductUpdateConfig> allConfigs = getAllConfigs();

            // Null check on result
            if (allConfigs == null || allConfigs.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'No configurations available');
                return null;
            }

            // Return config for requested status
            ProductUpdateConfig config = allConfigs.get(statusValue);

            if (config == null) {
                System.debug(LoggingLevel.INFO, 'No configuration found for status: ' + statusValue);
            }

            return config;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in getConfigForStatus: ' + e.getMessage());
            throw new AuraHandledException('Unable to load configuration for status: ' + e.getMessage());
        }
    }

    /**
     * Retrieves a Custom Label value by API name
     * Custom labels must be referenced explicitly in Apex
     * @param labelName API name of the Custom Label
     * @return Label value or the label name if not found
     */
    @AuraEnabled(cacheable=true)
    public static String getLabel(String labelName) {
        if (String.isBlank(labelName)) {
            return '';
        }

        // Map label names to their actual System.Label references
        // Custom labels cannot be accessed dynamically in Apex
        switch on labelName {
            when 'RES_Product_Update_Warning_Active' {
                return System.Label.RES_Product_Update_Warning_Active;
            }
            when 'RES_Product_Update_Warning_Hold' {
                return System.Label.RES_Product_Update_Warning_Hold;
            }
            when 'RES_Product_Update_Success' {
                return System.Label.RES_Product_Update_Success;
            }
            when 'RES_Product_Update_Comments_Required' {
                return System.Label.RES_Product_Update_Comments_Required;
            }
            when 'RES_Product_Update_Comments_Min_Length' {
                return System.Label.RES_Product_Update_Comments_Min_Length;
            }
            when 'RES_Product_Update_Error_Generic' {
                return System.Label.RES_Product_Update_Error_Generic;
            }
            when 'RES_Product_Update_Status_Active_Info' {
                return System.Label.RES_Product_Update_Status_Active_Info;
            }
            when 'RES_Product_Update_Status_Hold_Info' {
                return System.Label.RES_Product_Update_Status_Hold_Info;
            }
            when 'RES_Product_Update_Modal_Title' {
                return System.Label.RES_Product_Update_Modal_Title;
            }
            when 'RES_Product_Update_Confirm_Title' {
                return System.Label.RES_Product_Update_Confirm_Title;
            }
            when else {
                // If label not found, return the label name
                System.debug('Label not found: ' + labelName);
                return labelName;
            }
        }
    }

    /**
     * Retrieves all Product Update related labels
     * @return Map of label name => label value
     * @throws AuraHandledException if label retrieval fails
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getAllLabels() {
        try {
            Map<String, String> labels = new Map<String, String>();

            // Define all label names used by the modal
            // Note: This list should be kept in sync with available Custom Labels
            List<String> labelNames = new List<String>{
                'RES_Product_Update_Warning_Active',
                'RES_Product_Update_Warning_Hold',
                'RES_Product_Update_Success',
                'RES_Product_Update_Comments_Required',
                'RES_Product_Update_Comments_Min_Length',
                'RES_Product_Update_Error_Generic',
                'RES_Product_Update_Status_Active_Info',
                'RES_Product_Update_Status_Hold_Info',
                'RES_Product_Update_Modal_Title',
                'RES_Product_Update_Confirm_Title'
            };

            // Bulkified processing - get all labels in one loop
            // No SOQL/DML involved, stays under governor limits
            for (String labelName : labelNames) {
                if (String.isNotBlank(labelName)) {
                    labels.put(labelName, getLabel(labelName));
                }
            }

            return labels;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error retrieving labels: ' + e.getMessage());
            throw new AuraHandledException('Unable to load labels: ' + e.getMessage());
        }
    }

    /**
     * Wrapper class for Product Update Configuration
     * AuraEnabled properties for LWC consumption
     */
    public class ProductUpdateConfig {
        @AuraEnabled public String statusValue;
        @AuraEnabled public String warningLabelName;
        @AuraEnabled public String warningMessage;
        @AuraEnabled public Boolean requiresWarning;
        @AuraEnabled public String targetStatus;
        @AuraEnabled public Integer minCommentLength;
    }
}
