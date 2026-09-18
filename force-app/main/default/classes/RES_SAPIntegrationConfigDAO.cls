/**
 * Class Name   : RES_SAPIntegrationConfigDAO
 * Description  : Data Access Object (DAO) layer for the Metadata object.
 *                Provides standardized methods for querying and retrieving
 *                Lead records within the application.
 *
 * Framework Rule:
 *      - All DAO layers must extend RES_BaseDAOLayer.
 *      - Each implementation must override getSObjectName()
 *        to specify the associated SObject.
 */

/**
 * =============================================================================
 * QUERY EXECUTION GUIDELINES
 * =============================================================================
 *
 * 1. Standard Query Execution
 *    Method:
 *      executeQuery(String soql,
 *                   String cacheSuffix,
 *                   Boolean useCache,
 *                   Map<String, Object> bindVars,
 *                   AccessLevel accessLevel)
 *    To get Map<id, Sobject> use executeQueryToMap(<Same Params as above>).
 * 
 *    Usage Guidelines:
 *      - Enable caching ONLY for static queries where data does not change frequently.
 *      - For dynamic queries:
 *            • Set useCache = false
 *            • Set cacheSuffix = ''
 *
 * 2. Batch Query Execution
 *    Method:
 *      executeBatchQuery(String soql,
 *                        Map<String, Object> bindVars,
 *                        AccessLevel accessLevel)
 * =============================================================================
 */

public without sharing class RES_SAPIntegrationConfigDAO extends RES_BaseDAOLayer {
    public RES_SAPIntegrationConfigDAO() {}

    protected override String getSObjectName() {
        return 'RES_SAP_Integration_Config__mdt';
    }

    public RES_SAP_Integration_Config__mdt getSAPIntegrationConfigByDeveloperName(String developerName) {
        Map<String, Object> bindVars = new Map<String, Object>{
            'developerName' => developerName
        };

        String soql =
            'SELECT DeveloperName, Id, RES_Sync_Fields__c ' +
            'FROM RES_SAP_Integration_Config__mdt ' +
            'WHERE DeveloperName = :developerName ' +
            'LIMIT 1';

        List<RES_SAP_Integration_Config__mdt> configs =
            (List<RES_SAP_Integration_Config__mdt>) executeQuery(
                soql,
                '',
                false,
                bindVars,
                AccessLevel.SYSTEM_MODE
            );

        return configs.isEmpty() ? null : configs[0];
    }
}