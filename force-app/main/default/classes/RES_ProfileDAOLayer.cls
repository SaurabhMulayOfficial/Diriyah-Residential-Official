/**
 * Class Name   : RES_ProfileDAOLayer
 * Description  : Data Access Object (DAO) layer for the Profile object.
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

public without sharing class RES_ProfileDAOLayer extends RES_BaseDAOLayer{
    protected override String getSObjectName() {
        return 'Profile';
    }
    private static final String CLASS_NAME = 'RES_ProfileDAOLayer';

    public String getCurrentUserProfileName(){
        Id currentUserProfileId         = UserInfo.getProfileId();
        Map<String, Object> bindVars    = new Map<String, Object> ();
        bindVars.put('currentUserProfileId', currentUserProfileId);
        String soql = 'SELECT Name FROM Profile WHERE Id =: currentUserProfileId LIMIT 1';
        List<Profile> profileLst = (List<Profile>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
        if(!profileLst.isEmpty()){
            return profileLst[0].Name;
        }
        return null;
    }
}