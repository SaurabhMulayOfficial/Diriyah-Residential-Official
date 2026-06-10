/**
 * Class Name   : RES_ContactDAOLayer
 * Description  : Data Access Object (DAO) layer for the Lead object.
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
public without sharing class RES_ContactDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'Contact';
    }
    public List<Contact> getContactByMobilePhone(Set<String> mobilePhone){
        Map<String,Object> bindVars = new Map<String, Object>();
        bindVars.put('mobilePhone', mobilePhone);
        String soql = 'SELECT Id, MobilePhone FROM Contact WHERE MobilePhone IN: mobilePhone';
        List<Contact> contactList = executeQuery(soql, 'getContactByMobilePhone', true, bindVars, AccessLevel.SYSTEM_MODE);
        return contactList;
    }

    public Contact getContactById(Id contactId) {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('contactId', contactId);
        String soql = 'SELECT Id, Name, Title, Phone, Email, MobilePhone, LeadSource FROM Contact WHERE Id = :contactId LIMIT 1';
        List<SObject> results = executeQuery(soql, '', true, bindVars, AccessLevel.SYSTEM_MODE);
        return results != null && !results.isEmpty() ? (Contact) results[0] : null;
    }
}