/**
 * Class Name   : RES_AccountDAOLayer
 * Description  : Data Access Object (DAO) layer for the Account object.
 *                Provides standardized methods for querying and retrieving
 *                Account records within the application.
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
    public Map<Id, Account> getAccountsByIds(Set<Id> accountIds) {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('accountIds', accountIds);
        String soql = 'SELECT Id, RES_External_Key__c ' +
                        'FROM Account ' +
                        'WHERE Id IN :accountIds';
        Map<Id, Account> result = new Map<Id, Account>();
        for (SObject record : executeQueryToMap(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE).values()) {
            result.put(record.Id, (Account) record);
        }
        return result;
    }

    public Account getAccountById(Id accountId) {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('accountId', accountId);
        String soql = 'SELECT Id, Name, Type, Phone, Website, Rating, ' +
                            'IsPersonAccount, AccountSource, ' +
                            'PersonMobilePhone, PersonEmail, Owner.Name ' +
                            'FROM Account ' +
                            'WHERE Id = :accountId ' +
                            'LIMIT 1';
        List<SObject> results = executeQuery(soql, '', true, bindVars, AccessLevel.SYSTEM_MODE);
        return results != null && !results.isEmpty() ? (Account) results[0] : null;
    }

    public Map<Id, Account> getAccountsForSyncByIds(Set<Id> accountIds) {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('accountIds', accountIds);
        String soql = 'SELECT Id, Name, Type, RecordTypeId, RecordType.DeveloperName, IsPersonAccount, ' +
                        'PersonTitle, FirstName, LastName, Fax, ' +
                        'Phone, PersonMobilePhone, PersonEmail, ' +
                        'BillingStreet, BillingCity, BillingPostalCode, BillingCountryCode, BillingStateCode, ' +
                        'PersonGenderIdentity, ' +
                        'RES_Language__pc, RES_Nationality__pc, RES_Date_of_Birth__pc, RES_Marital_Status__pc, ' +
                        'RES_Full_Arabic_Name__c, RES_Full_Arabic_Name__pc, RES_Company_Additional_Name__c, ' +
                        'RES_Corporate_Title__c, ' +
                        'RES_House_Number__c, RES_District__c, RES_PO_Box__c, RES_Extension__c, ' +
                        'RES_Identification_Type__c, RES_Identification_Number__c, ' +
                        'RES_ID_Entry_Date__c, RES_ID_Valid_From_Date__c, RES_ID_Valid_to_Date__c, ' +
                        'RES_Company_Code__c, RES_Reconciliation_Account__c, RES_Planning_Group__c, ' +
                        'RES_SIMAH_Consent__c, RES_Consent_Form_Received_Date__c, ' +
                        'RES_VIP_Customer__c, RES_Bank_Customer__c, ' +
                        'RES_Tax_Category__c, RES_Tax_Number__c, ' +
                        'RES_Relationship_Type__c, RES_BP_Role__c, RES_Account_Group__c, ' +
                        'RES_SAP_ADDR_NUMBER__c, ' +
                        'RES_External_Key__c ' +
                        'FROM Account ' +
                        'WHERE Id IN :accountIds';
        Map<Id, Account> result = new Map<Id, Account>();
        for (SObject record : executeQueryToMap(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE).values()) {
            result.put(record.Id, (Account) record);
        }
        return result;
    }
}