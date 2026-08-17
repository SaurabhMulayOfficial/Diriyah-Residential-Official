/**
 * Class Name   : RES_Product2DAOLayer
 * Description  : Data Access Object (DAO) layer for the Product2 object.
 *                Provides standardized methods for querying and retrieving
 *                Product2 records within the application.
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
public with sharing class RES_Product2DAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'Product2';
    }

    public List<Product2> getProductsByBatchId(Id batchId) {
        if (batchId == null) {
            return new List<Product2>();
        }
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('batchId', batchId);
        String soql = 'SELECT Id, IsActive, RES_Pending_Amendment__c FROM Product2 WHERE RES_Product_Approval_Batch__c = :batchId';
        return (List<Product2>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public Database.QueryLocator getProductQueryLocatorByBatchId(Id batchId) {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('batchId', batchId);
        String soql = 'SELECT Id, IsActive, RES_Pending_Amendment__c FROM Product2 WHERE RES_Product_Approval_Batch__c = :batchId';
        return executeBatchQuery(soql, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public List<Product2> getProductsByIds(Set<Id> productIds) {
    if (productIds == null || productIds.isEmpty()) {
        return new List<Product2>();
    } 
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('productIds', productIds);
        String soql = 'SELECT Id, RES_Unit_Status__c, RES_HardBlock_Start__c, RES_Is_In_Soft_Hold_Extension__c, RES_Soft_Hold_Start__c, RES_Soft_Hold_Until__c FROM Product2 WHERE Id IN :productIds';
        return (List<Product2>) executeQuery(soql,'', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

}