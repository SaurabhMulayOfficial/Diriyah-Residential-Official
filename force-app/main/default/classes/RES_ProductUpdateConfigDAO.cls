/**
 * Class Name   : RES_ProductUpdateConfigDAO
 * Description  : Data Access Object (DAO) layer for the RES_Product_Update_Config__mdt object.
 *                Provides standardized methods for querying and retrieving
 *                RES_Product_Update_Config__mdt records within the application.
 *
 * Framework Rule:
 *      - All DAO layers must extend RES_BaseDAOLayer.
 *      - Each implementation must override getSObjectName()
 *        to specify the associated SObject.
 *
 * Governor Limits:
 *      - Custom Metadata queries do NOT count against SOQL limits
 *      - Caching is enabled to minimize repeated queries
 *      - All queries use AccessLevel.SYSTEM_MODE for consistency
 */
public without sharing class RES_ProductUpdateConfigDAO extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'RES_Product_Update_Config__mdt';
    }

    /**
     * Retrieves all active update configurations.
     * Uses caching to avoid repeated queries.
     * Custom Metadata queries do NOT count against governor limits.
     *
     * @return List of active RES_Product_Update_Config__mdt records (never null)
     */
    public List<RES_Product_Update_Config__mdt> getActiveConfigs() {
        try {
            String soql =
                'SELECT ' +
                'DeveloperName, ' +
                'MasterLabel, ' +
                'RES_Field_API_Name__c, ' +
                'RES_Field_Label__c, ' +
                'RES_Is_Required__c, ' +
                'RES_Is_Updateable__c, ' +
                'RES_Display_Order__c, ' +
                'RES_Active__c ' +
                'FROM RES_Product_Update_Config__mdt ' +
                'WHERE RES_Active__c = true ' +
                'ORDER BY RES_Display_Order__c ASC';

            List<RES_Product_Update_Config__mdt> results =
                (List<RES_Product_Update_Config__mdt>) executeQuery(
                    soql,
                    'activeProductUpdateConfigs',
                    true, // Enable caching
                    new Map<String, Object>(),
                    AccessLevel.SYSTEM_MODE
                );

            // Return empty list instead of null for safer handling
            return results != null ? results : new List<RES_Product_Update_Config__mdt>();

        } catch (Exception e) {
            // Log error and return empty list to prevent null pointer exceptions
            System.debug(LoggingLevel.ERROR, 'Error in getActiveConfigs: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
            return new List<RES_Product_Update_Config__mdt>();
        }
    }

    /**
     * Retrieves a specific configuration by Developer Name.
     * Uses caching with developer name as cache key for performance.
     *
     * @param developerName The Developer Name of the configuration record
     * @return RES_Product_Update_Config__mdt record or null if not found
     */
    public RES_Product_Update_Config__mdt getConfigByDeveloperName(String developerName) {
        try {
            // Validate input parameter
            if (String.isBlank(developerName)) {
                System.debug(LoggingLevel.WARN, 'getConfigByDeveloperName called with blank developer name');
                return null;
            }

            String soql =
                'SELECT ' +
                'DeveloperName, ' +
                'MasterLabel, ' +
                'RES_Field_API_Name__c, ' +
                'RES_Field_Label__c, ' +
                'RES_Is_Required__c, ' +
                'RES_Is_Updateable__c, ' +
                'RES_Display_Order__c, ' +
                'RES_Active__c ' +
                'FROM RES_Product_Update_Config__mdt ' +
                'WHERE DeveloperName = :developerName ' +
                'LIMIT 1';

            Map<String, Object> bindVars = new Map<String, Object>{
                'developerName' => developerName
            };

            List<RES_Product_Update_Config__mdt> results =
                (List<RES_Product_Update_Config__mdt>) executeQuery(
                    soql,
                    'configByDevName_' + developerName,
                    true, // Enable caching
                    bindVars,
                    AccessLevel.SYSTEM_MODE
                );

            // Safe null handling
            if (results == null || results.isEmpty()) {
                System.debug(LoggingLevel.INFO, 'No config found for developer name: ' + developerName);
                return null;
            }

            return results[0];

        } catch (Exception e) {
            // Log error and return null to prevent exceptions
            System.debug(LoggingLevel.ERROR, 'Error in getConfigByDeveloperName: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
            return null;
        }
    }
}
