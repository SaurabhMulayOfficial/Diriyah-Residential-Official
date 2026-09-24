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
public with sharing class RES_AccountDAOLayer extends RES_BaseDAOLayer {
    
    protected override String getSObjectName() {
        return 'Account';
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

    /**
     * @description Returns Person Accounts whose email or mobile phone matches the
     *              supplied Lead details. Used by RES_AccountMatcherController to find
     *              existing Person Accounts for a Residential Individual Lead.
     * @param email        Lead email to match against Account.PersonEmail
     * @param mobilePhone  Lead mobile to match against Account.PersonMobilePhone
     * @return List of matching Person Account records (empty if no criteria supplied).
     */
    public List<Account> getPersonAccountsByLeadDetails(String email, String mobilePhone) {
        List<Account> matches = new List<Account>();
        if (String.isBlank(email) && String.isBlank(mobilePhone)) {
            return matches;
        }
        Map<String, Object> bindVars = new Map<String, Object>();
        List<String> conditions = new List<String>();
        if (String.isNotBlank(email)) {
            bindVars.put('email', email);
            conditions.add('PersonEmail = :email');
        }
        if (String.isNotBlank(mobilePhone)) {
            bindVars.put('mobilePhone', mobilePhone);
            conditions.add('PersonMobilePhone = :mobilePhone');
        }
        String soql = 'SELECT Id, Name, Type, Phone, Website, Rating, ' +
                            'IsPersonAccount, AccountSource, ' +
                            'PersonMobilePhone, PersonEmail, Owner.Name ' +
                            'FROM Account ' +
                            'WHERE IsPersonAccount = true ' +
                            'AND (' + String.join(conditions, ' OR ') + ')';
        List<SObject> results = executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
        return results != null ? (List<Account>) results : matches;
    }

    /**
     * @description Returns business (non-Person) Accounts whose Name matches the supplied
     *              Lead Company and that have a Website populated (so the caller can compare
     *              the Account website domain against the Lead email domain).
     * @param company  Lead Company name to match against Account.Name
     * @return List of matching business Account records (empty if no company supplied).
     */
    public List<Account> getCompanyAccountsByLeadDetails(String company) {
        List<Account> matches = new List<Account>();
        if (String.isBlank(company)) {
            return matches;
        }
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('company', company);
        String soql = 'SELECT Id, Name, Type, Phone, Website, Rating, ' +
                            'IsPersonAccount, AccountSource, ' +
                            'PersonMobilePhone, PersonEmail, Owner.Name ' +
                            'FROM Account ' +
                            'WHERE IsPersonAccount = false ' +
                            'AND Name = :company ' +
                            'AND Website != null';
        List<SObject> results = executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
        return results != null ? (List<Account>) results : matches;
    }

    /**
     * @description Bulkified query retrieving Account records and fields required for 
     *              SAP S/4HANA Business Partner Integration payload hydration.
     * @param accountIds Set of Account IDs to query
     * @return List of Account records with integration fields
     */
    public List<Account> getAccountsByIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Account>();
        }
        Map<String, Object> bindVars = new Map<String, Object>{ 'accountIds' => accountIds };
        String soql = 'SELECT Id, IsPersonAccount, RecordTypeId, Type, PersonTitle, LastName, Name, Phone, ' +
                      'PersonGenderIdentity, DIR_SAP_Business_Partner_ID__c, RES_Language__c, RES_Marital_Status__c, ' +
                      'RES_Nationality__c, RES_Date_of_Birth__c, RES_NAME1__c, RES_NAME2__c, RES_KTOKD__c, ' +
                      'RES_Relationship_Type__c, RES_Company_Additional_Name__c, RES_BP_NUMBER__c, BillingCity, ' +
                      'BillingPostalCode, BillingStreet, BillingCountry, PersonEmail, Fax, RES_Full_Arabic_Name__c, ' +
                      'RES_SIMAH_Consent__c, RES_VIP_Customer__c, RES_Bank_Customer__c, RES_Consent_Form_Received_Date__c ' +
                      'FROM Account WHERE Id IN :accountIds';
        List<SObject> results = executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
        return results != null ? (List<Account>) results : new List<Account>();
    }
}