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

    // Returns all contacts related to the given accounts, grouped by AccountId.
    public Map<Id, List<Contact>> getContactsByAccountIds(Set<Id> accountIds) {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('accountIds', accountIds);
        String soql = 'SELECT Id, AccountId, LastName, Salutation, RES_Contact_Person_End_Date__c, RES_SAP_Contact_Id__c ' +
                      'FROM Contact ' +
                      'WHERE AccountId IN :accountIds ' +
                      'ORDER BY CreatedDate ASC';
        List<SObject> results = executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
        Map<Id, List<Contact>> contactsByAccountId = new Map<Id, List<Contact>>();
        if (results != null) {
            for (SObject s : results) {
                Contact c = (Contact) s;
                if (!contactsByAccountId.containsKey(c.AccountId)) {
                    contactsByAccountId.put(c.AccountId, new List<Contact>());
                }
                contactsByAccountId.get(c.AccountId).add(c);
            }
        }
        return contactsByAccountId;
    }

    // Nationality (picklist) and its Document Nationality text counterpart
    public Map<Id, Contact> getContactsNationalityByIds(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new Map<Id, Contact>();
        }
        Map<String, Object> bindVars = new Map<String, Object>{ 'contactIds' => contactIds };
        String soql = 'SELECT Id, RES_Nationality__c, RES_Document_Nationality__c ' +
                      'FROM Contact ' +
                      'WHERE Id IN :contactIds';
        return new Map<Id, Contact>((List<Contact>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE));
    }
}
