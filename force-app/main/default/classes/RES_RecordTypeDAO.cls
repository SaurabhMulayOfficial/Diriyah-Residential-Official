/**
 * Class Name   : RES_RecordTypeDAO
 * Description  : Data Access Object (DAO) layer for the RecordType object.
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

public with sharing class RES_RecordTypeDAO extends RES_BaseDAOLayer {
    protected override String getSObjectName(){
        return 'RecordType';
    }

    public Map<Id, RecordType> getRecordTypes(Set<Id> recordTypeId, String sObjectName){
        Map<String,Object> bindVars = new Map<String,Object>();
        bindVars.put('recordTypeId', recordTypeId);
        bindVars.put('sObjectName', sObjectName);
        
        String soql = 'SELECT Id, developerName FROM RecordType WHERE Id IN :recordTypeId AND SObjectType = :sObjectName';
        Map<Id, SObject> rawMap = executeQueryToMap(soql, 'recordTypes'+sObjectName, true, bindVars, AccessLevel.SYSTEM_MODE);

        Map<Id, RecordType> recordTypeMap = new Map<Id, RecordType>();

        for (Id key : rawMap.keySet()) {
            recordTypeMap.put(key, (RecordType) rawMap.get(key));
        }
        return recordTypeMap;
    }

    public List<RecordType> getActiveRecordTypesBySObject(String sObjName) {
        // 1. Prepare Bind Variables
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('sObjName', sObjName);
        
        // 2. Define SOQL
        String soql = 'SELECT Id, Name, DeveloperName ' + 
                      'FROM RecordType ' + 
                      'WHERE SObjectType = :sObjName ' + 
                      'AND IsActive = true ' + 
                      'ORDER BY Name';
        
        // 3. Execute via Base Layer
        // cacheSuffix is 'active_' + sObjName to keep caches distinct
        List<SObject> results = executeQuery(
            soql, 
            'active_' + sObjName, 
            true, 
            bindVars, 
            AccessLevel.SYSTEM_MODE
        );

        return (List<RecordType>) results;
    }

    public RecordType getActiveRecordTypeById(Id recordTypeId, String sObjectName) {
        // 1. Prepare Bind Variables
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('rtId', recordTypeId);
        bindVars.put('sObjName', sObjectName);

        // 2. Define SOQL (aligned with your requested query)
        String soql = 'SELECT Id, Name, DeveloperName ' +
                      'FROM RecordType ' +
                      'WHERE Id = :rtId ' +
                      'AND SObjectType = :sObjName ' +
                      'AND IsActive = true ' +
                      'LIMIT 1';

        // 3. Execute via Base Layer
        // We use cacheSuffix 'single_' + recordTypeId to ensure unique caching
        List<SObject> results = executeQuery(
            soql, 
            'single_' + (String)recordTypeId, 
            true, 
            bindVars, 
            AccessLevel.SYSTEM_MODE
        );

        // 4. Handle List to Single Record conversion
        return (results.isEmpty()) ? null : (RecordType) results[0];
    }


}