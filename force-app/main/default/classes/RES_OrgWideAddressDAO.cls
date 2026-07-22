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

public without sharing class RES_OrgWideAddressDAO extends RES_BaseDAOLayer {
    public RES_OrgWideAddressDAO() {}

    protected override String getSObjectName() {
        return 'OrgWideEmailAddress';
    }

    public List<OrgWideEmailAddress> getOrgWideAddressByDisplayName(String displayName){
        Map<String,Object> bindvars = new Map<String, Object>();
        bindvars.put('displayName', displayName);

        String soql = 'SELECT Id, DisplayName FROM OrgWideEmailAddress WHERE DisplayName =: displayName';
        return (List<OrgWideEmailAddress>) executeQuery(soql, 'getOrgWideAddressByDisplayName', true, bindvars, AccessLevel.SYSTEM_MODE);
    }
}