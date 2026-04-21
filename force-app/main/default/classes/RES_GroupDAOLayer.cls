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

public with sharing class RES_GroupDAOLayer extends RES_BaseDAOLayer {
    public RES_GroupDAOLayer() {}
    protected override String getSObjectName() {
        return 'Group';
    }

    public Map<String,Id> getQueueMappingbyIds(Set<String> queueDevNames){
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('queueDevNames', queueDevNames);
        String soql = 'SELECT Id, developerName FROM Group WHERE developerName IN: queueDevNames';
        List<Group> queue = executeQuery(soql, 'getQueueByNames', true, bindVars, AccessLevel.SYSTEM_MODE);
        Map<String, Id> queueMapping = new Map<String, Id>();

        for(Group g: queue){
            queueMapping.put(g.DeveloperName, g.Id);
        }

        return queueMapping;
    }

}