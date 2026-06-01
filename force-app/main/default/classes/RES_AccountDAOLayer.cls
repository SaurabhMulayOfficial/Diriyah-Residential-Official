/**
 * Class Name   : RES_AccountDAOLayer
 * Description  : Data Access Object (DAO) layer for the Account object.
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
public with sharing class RES_AccountDAOLayer extends RES_BaseDAOLayer{
    protected override String getSObjectName() {
        return 'Account';
    }
    public Account getAccountById(Id accountId) {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('accountId', accountId);
        String soql = 'SELECT Id, Name, Type, Phone, Website, Site, OwnerId, Owner.Name, IsPersonAccount FROM Account WHERE Id = :accountId LIMIT 1';
        List<SObject> results = executeQuery(soql, '', true, bindVars, AccessLevel.SYSTEM_MODE);
        return results != null && !results.isEmpty() ? (Account) results[0] : null;
    }
}