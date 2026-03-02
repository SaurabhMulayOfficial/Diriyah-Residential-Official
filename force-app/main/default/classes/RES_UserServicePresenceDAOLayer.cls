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

public with sharing class RES_UserServicePresenceDAOLayer extends RES_BaseDAOLayer {
    public RES_UserServicePresenceDAOLayer() {
    }

    protected override String getSObjectName() {
        return 'UserServicePresence';
    }


    public List<UserServicePresence> getActiveUsers(){
        String soql = 'SELECT Id, UserId, ServicePresenceStatusId, ServicePresenceStatus.MasterLabel ' +
              'FROM UserServicePresence ' +
              'WHERE IsCurrentState = true';
        return (List<UserServicePresence>) executeQuery(soql, '', false, null, AccessLevel.SYSTEM_MODE);
    }
}