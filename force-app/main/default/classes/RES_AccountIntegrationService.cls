/**
 * @description
 * Integration service responsible for synchronizing Salesforce Account (Business Partner)
 * records with SAP S/4HANA via the Business Partner API.
 *
 * Extends RES_BaseIntegrationCalloutService to leverage the common integration
 * framework for HTTP callout configuration, retry handling, and response processing.
 *
 * On a successful insert response, the SAP-assigned BP number is stored in
 * RES_External_Key__c on the Account record.
 *
 * Both Person Account and Organization/Company Account payloads share the same
 * structure; company accounts include additional fields (TT_COMPANY_CODES,
 * RES_Company_Additional_Name).
 *
 * @author Nitin Marathe
 */

public with sharing class RES_AccountIntegrationService extends RES_BaseIntegrationCalloutService {

    public RES_AccountIntegrationService(String requestMethod) {
        super();
        List<RES_API_Configuration__mdt> apiConfigList = new RES_APIConfigurationsDAO().getAPIConfiguration(requestMethod, 'Business_Partner_API');

        if (apiConfigList.isEmpty()) {
            throw new RES_IntegrationException('No API configuration found for Account integration with request method: ' + requestMethod);
        }

        setEndpoint(apiConfigList[0].RES_Endpoint__c);

        Integer maxRetries = apiConfigList[0].RES_Max_Retries__c != null ? Integer.valueOf(apiConfigList[0].RES_Max_Retries__c) : 3;
        Integer timeout = apiConfigList[0].RES_Callout_Timeout__c != null ? Integer.valueOf(apiConfigList[0].RES_Callout_Timeout__c) : 10000;

        String sapToken = new RES_SAPTokenProvider().getToken();
        if (sapToken == null || String.isBlank(sapToken)) {
            throw new RES_IntegrationException('Failed to retrieve SAP token for Account integration.');
        }

        Map<String, String> headers = new Map<String, String>();
        if (apiConfigList[0].RES_Headers__c != null) {
            Map<String, Object> inputHeaders = (Map<String, Object>) JSON.deserializeUntyped(apiConfigList[0].RES_Headers__c);
            for (String key : inputHeaders.keySet()) {
                headers.put(key, String.valueOf(inputHeaders.get(key)));
            }
        }

        headers.put('Authorization', 'Bearer ' + sapToken);
        setHeaders(headers);
        setMaxRetries(maxRetries);
        setRequestMethod(requestMethod);
        setTimeout(timeout);
    }

    private static String blankIfNull(String value) {
        return value == null ? '' : value;
    }

    private static String mapLanguageCode(String languageApiName) {
        if (languageApiName == 'AR') {
            return 'A';
        }
        return 'E';
    }

    private static RES_AccountRequestWrapper buildAccountWrapper(Account acc, String triggerContext, List<Contact> relatedContacts) {
        RES_AccountRequestWrapper wrapper = new RES_AccountRequestWrapper();

        Boolean isPersonAccount = acc.IsPersonAccount;
        String recordTypeDeveloperName = acc.RecordType != null ? acc.RecordType.DeveloperName : null;
        Boolean isInsert = triggerContext == 'I';

        Contact firstRelatedContact = (!isPersonAccount && relatedContacts != null && !relatedContacts.isEmpty())
            ? relatedContacts[0] : null;

        wrapper.Id = acc.Id;
        // RecordTypeId: '1' for PersonAccount, '2' for Company
        wrapper.RecordTypeId = (recordTypeDeveloperName == 'PersonAccount') ? '1' : '2';
        wrapper.Type = blankIfNull(acc.Type);
        // PersonTitle maps to RES_Corporate_Title__c
        wrapper.PersonTitle = blankIfNull(acc.RES_Corporate_Title__c);
        wrapper.LastName = isPersonAccount
            ? blankIfNull(acc.LastName)
            : (firstRelatedContact != null ? blankIfNull(firstRelatedContact.LastName) : '');
        wrapper.Name = isPersonAccount ? blankIfNull(acc.Name) : '';
        wrapper.RES_Language = mapLanguageCode(acc.RES_Language__pc);
        wrapper.Phone = blankIfNull(acc.Phone);
        wrapper.PersonGenderIdentity =blankIfNull(acc.PersonGenderIdentity);
        wrapper.RES_Marital_Status = blankIfNull(acc.RES_Marital_Status__pc);
        wrapper.RES_Nationality = blankIfNull(acc.RES_Nationality__pc);
        wrapper.RES_Date_of_Birth = isPersonAccount && acc.PersonBirthdate != null ? String.valueOf(acc.PersonBirthdate) : '';
        wrapper.RES_Company_Additional_Name = ''; // always blank per payload spec
        wrapper.RES_OBJECT_TASK = triggerContext;
        // RES_BP_NUMBER: blank on first insert; pass RES_External_Key__c on update (must not be null)
        wrapper.RES_BP_NUMBER = isInsert ? '' : blankIfNull(acc.RES_External_Key__c);
        wrapper.RES_NAME1 = isPersonAccount ? '' : blankIfNull(acc.Name);
        wrapper.RES_NAME2 = '';
        wrapper.RES_KTOKD = blankIfNull(acc.RES_Account_Group__c);
        wrapper.RES_Relationship_Type = blankIfNull(acc.RES_Relationship_Type__c);
        wrapper.Change_Indicator = triggerContext;
        // Fullname: only for Company Account; blank for PersonAccount
        wrapper.Fullname = isPersonAccount ? '' : blankIfNull(acc.Name);
        wrapper.Account_Category = blankIfNull(acc.RES_Account_Group__c);

        RES_AccountRequestWrapper.TaxNumbers taxNumbers = new RES_AccountRequestWrapper.TaxNumbers();
        RES_AccountRequestWrapper.TaxItem taxItem = new RES_AccountRequestWrapper.TaxItem();
        taxItem.OBJECT_TASK = triggerContext;
        if (isPersonAccount) {
            taxItem.TAXTYPE = 'SA0';
            taxItem.TAXNUMBER = '000';
        } else {
            taxItem.TAXTYPE = blankIfNull(acc.RES_Tax_Category__c);
            taxItem.TAXNUMBER = blankIfNull(acc.RES_Tax_Number__c);
        }
        taxNumbers.item = taxItem;
        wrapper.TT_TAX_NUMBERS = taxNumbers;

        RES_AccountRequestWrapper.AddressItem addressItem = new RES_AccountRequestWrapper.AddressItem();
        addressItem.OBJECT_TASK = triggerContext;
        // ADDRNUMBER: blank on insert; on update pass the stored SAP address number (must not be null)
        addressItem.ADDRNUMBER = isInsert ? '' : blankIfNull(acc.RES_SAP_ADDR_NUMBER__c);
        addressItem.CITY = blankIfNull(acc.BillingCity);
        addressItem.POSTL_COD1 = blankIfNull(acc.BillingPostalCode);
        addressItem.STREET = blankIfNull(acc.BillingStreet);
        addressItem.COUNTRY = blankIfNull(acc.BillingCountryCode);
        addressItem.LANGU = mapLanguageCode(acc.RES_Language__pc);

        RES_AccountRequestWrapper.PhoneItem phoneItem = new RES_AccountRequestWrapper.PhoneItem();
        phoneItem.OBJECT_TASK = triggerContext;
        phoneItem.TELEPHONE = blankIfNull(acc.Phone);
        phoneItem.EXTENSION = acc.RES_Extension__c != null ? String.valueOf(acc.RES_Extension__c) : '';
        phoneItem.COUNTRY = blankIfNull(acc.BillingCountryCode);
        RES_AccountRequestWrapper.Phones phones = new RES_AccountRequestWrapper.Phones();
        phones.item = phoneItem;
        addressItem.TT_PHONES = phones;

        RES_AccountRequestWrapper.FaxItem faxItem = new RES_AccountRequestWrapper.FaxItem();
        faxItem.OBJECT_TASK = triggerContext;
        faxItem.FAX = blankIfNull(acc.Fax);
        faxItem.COUNTRY = blankIfNull(acc.BillingCountryCode);
        RES_AccountRequestWrapper.Faxes faxes = new RES_AccountRequestWrapper.Faxes();
        faxes.item = faxItem;
        addressItem.TT_FAXES = faxes;

        RES_AccountRequestWrapper.EmailItem emailItem = new RES_AccountRequestWrapper.EmailItem();
        emailItem.OBJECT_TASK = triggerContext;
        emailItem.E_MAIL = blankIfNull(acc.PersonEmail);
        RES_AccountRequestWrapper.Emails emails = new RES_AccountRequestWrapper.Emails();
        emails.item = emailItem;
        addressItem.TT_EMAILS = emails;

        RES_AccountRequestWrapper.Addresses addresses = new RES_AccountRequestWrapper.Addresses();
        addresses.item = addressItem;
        wrapper.TT_ADDRESSES = addresses;

        RES_AccountRequestWrapper.RoleItem roleItem = new RES_AccountRequestWrapper.RoleItem();
        roleItem.OBJECT_TASK = triggerContext;
        // Default to ZTR602 (Owner) when no BP Role is selected
        roleItem.DATA_KEY = String.isBlank(acc.RES_BP_Role__c) ? 'ZTR602' : acc.RES_BP_Role__c;
        RES_AccountRequestWrapper.Roles roles = new RES_AccountRequestWrapper.Roles();
        roles.item = new List<RES_AccountRequestWrapper.RoleItem>{ roleItem };
        wrapper.TT_ROLES = roles;

        // Always send Company Code and Identification blocks; blank values are passed as ""
        RES_AccountRequestWrapper.CompanyCodeWrapper ccWrapper = new RES_AccountRequestWrapper.CompanyCodeWrapper();
        ccWrapper.RES_Company_Code = blankIfNull(acc.RES_Company_Code__c);
        ccWrapper.RES_Reconciliation_Account = blankIfNull(acc.RES_Reconciliation_Account__c);
        ccWrapper.RES_Planning_Group = blankIfNull(acc.RES_Planning_Group__c);
        ccWrapper.Company_Code_Change_Indicator = triggerContext;
        wrapper.RES_Company_Codes = new List<RES_AccountRequestWrapper.CompanyCodeWrapper>{ ccWrapper };

        RES_AccountRequestWrapper.IdentificationItem identItem = new RES_AccountRequestWrapper.IdentificationItem();
        identItem.OBJECT_TASK = triggerContext;
        identItem.IDENTIFICATIONCATEGORY = blankIfNull(acc.RES_Identification_Type__c);
        // Person Account -> Identification Number; Company Account -> CR Number; blank is sent as ""
        identItem.IDENTIFICATIONNUMBER = isPersonAccount
            ? blankIfNull(acc.RES_Identification_Number__c)
            : blankIfNull(acc.RES_CR_number__c);
        identItem.IDENTRYDATE = acc.RES_ID_Entry_Date__c != null ? String.valueOf(acc.RES_ID_Entry_Date__c) : '';
        identItem.IDVALIDFROMDATE = acc.RES_ID_Valid_From_Date__c != null ? String.valueOf(acc.RES_ID_Valid_From_Date__c) : '';
        identItem.IDVALIDTODATE = acc.RES_ID_Valid_to_Date__c != null ? String.valueOf(acc.RES_ID_Valid_to_Date__c) : '';
        RES_AccountRequestWrapper.Identifications identifications = new RES_AccountRequestWrapper.Identifications();
        identifications.item = identItem;
        wrapper.TT_IDENTIFICATIONS = identifications;

        // TT_COMPANY_CODES: always two static entries per SAP spec
        RES_AccountRequestWrapper.CompanyCodeItem ccItem1 = new RES_AccountRequestWrapper.CompanyCodeItem();
        ccItem1.OBJECT_TASK = triggerContext;
        ccItem1.BUKRS = '9000';
        ccItem1.AKONT = '0000153001';
        RES_AccountRequestWrapper.CompanyCodeItem ccItem2 = new RES_AccountRequestWrapper.CompanyCodeItem();
        ccItem2.OBJECT_TASK = triggerContext;
        ccItem2.BUKRS = '1000';
        ccItem2.AKONT = '0000153005';
        RES_AccountRequestWrapper.CompanyCodes companyCodes = new RES_AccountRequestWrapper.CompanyCodes();
        companyCodes.item = new List<RES_AccountRequestWrapper.CompanyCodeItem>{ ccItem1, ccItem2 };
        wrapper.TT_COMPANY_CODES = companyCodes;

        wrapper.RES_CustomFields = buildCustomFields(acc, isPersonAccount);

        // Contact person fields — only populated for Company accounts (RecordTypeId = '2')
        if (isPersonAccount) {
            wrapper.CONTACT_PERSON_TASK = '';
            wrapper.CONTACT_PERSON_BP = '';
            wrapper.HAS_CONTACT_PERSON = '';
            wrapper.CONTACT_PERSON_GROUPING = '';
            wrapper.CONTACT_PERSON_TITLE = '';
            wrapper.CONTACT_PERSON_END_DATE = '';
        } else {
            Integer contactCount = (relatedContacts != null) ? relatedContacts.size() : 0;
            if (contactCount == 0) {
                // No related contact: send all contact person fields blank
                wrapper.CONTACT_PERSON_TASK = '';
                wrapper.CONTACT_PERSON_BP = '';
                wrapper.HAS_CONTACT_PERSON = '';
                wrapper.CONTACT_PERSON_GROUPING = '';
                wrapper.CONTACT_PERSON_TITLE = '';
                wrapper.CONTACT_PERSON_END_DATE = '';
            } else {
                wrapper.CONTACT_PERSON_TASK = triggerContext;
                // CONTACT_PERSON_BP: blank on insert; on update pass SAP contact id from related contact if available
                wrapper.CONTACT_PERSON_BP = isInsert ? '' : (
                    (firstRelatedContact != null && String.isNotBlank(firstRelatedContact.RES_SAP_Contact_Id__c))
                        ? firstRelatedContact.RES_SAP_Contact_Id__c : ''
                );
                wrapper.HAS_CONTACT_PERSON = 'X';
                wrapper.CONTACT_PERSON_GROUPING = 'Z009';
                wrapper.CONTACT_PERSON_TITLE = (firstRelatedContact != null && String.isNotBlank(firstRelatedContact.Salutation)) ? firstRelatedContact.Salutation : '';
                // Default end date when not provided
                wrapper.CONTACT_PERSON_END_DATE = (firstRelatedContact != null && firstRelatedContact.RES_Contact_Person_End_Date__c != null)
                    ? String.valueOf(firstRelatedContact.RES_Contact_Person_End_Date__c) : '2099-12-31';
            }
        }

        return wrapper;
    }

    private static List<RES_AccountRequestWrapper.CustomField> buildCustomFields(Account acc, Boolean isPersonAccount) {
        List<RES_AccountRequestWrapper.CustomField> customFields = new List<RES_AccountRequestWrapper.CustomField>();
        // RES_Full_Arabic_Name: PersonAccount uses __pc field; Company Account uses __c field
        customFields.add(new RES_AccountRequestWrapper.CustomField(
            'RES_Full_Arabic_Name',
            blankIfNull(isPersonAccount ? acc.RES_Full_Arabic_Name__pc : acc.RES_Full_Arabic_Name__c)
        ));
        customFields.add(new RES_AccountRequestWrapper.CustomField('RES_SIMAH_Consent', blankIfNull(acc.RES_SIMAH_Consent__c)));
        customFields.add(new RES_AccountRequestWrapper.CustomField('RES_VIP_Customer', acc.RES_VIP_Customer__c));
        customFields.add(new RES_AccountRequestWrapper.CustomField('RES_Bank_Customer', acc.RES_Bank_Customer__c));
        customFields.add(new RES_AccountRequestWrapper.CustomField(
            'RES_Consent_Form_Received_Date',
            acc.RES_Consent_Form_Received_Date__c != null
                ? acc.RES_Consent_Form_Received_Date__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                : ''
        ));
        return customFields;
    }

    public String hydrateRequestBody(List<Account> accounts, String triggerContext) {
        if (accounts == null || accounts.isEmpty()) {
            throw new RES_IntegrationException('No Account records provided for integration.');
        }

        // Re-query accounts to ensure all required fields (including IsPersonAccount) are available
        Set<Id> accountIds = new Set<Id>();
        for (Account acc : accounts) {
            accountIds.add(acc.Id);
        }
        Map<Id, Account> accountsById = new RES_AccountDAOLayer().getAccountsForSyncByIds(accountIds);
        List<Account> queriedAccounts = accountsById.values();

        // Query related contacts for all accounts in one SOQL call
        Map<Id, List<Contact>> contactsByAccountId = new RES_ContactDAOLayer().getContactsByAccountIds(accountIds);

        List<RES_AccountRequestWrapper> wrappers = new List<RES_AccountRequestWrapper>();
        for (Account acc : queriedAccounts) {
            List<Contact> relatedContacts = contactsByAccountId.containsKey(acc.Id)
                ? contactsByAccountId.get(acc.Id)
                : new List<Contact>();
            wrappers.add(buildAccountWrapper(acc, triggerContext, relatedContacts));
        }

        if (wrappers.isEmpty()) {
            throw new RES_IntegrationException('No valid Account records found for integration.');
        }

        if (wrappers.size() == 1) {
            return JSON.serialize(wrappers[0], true);
        }
        return JSON.serialize(wrappers, true);
    }

    // Set by processResponse when it has already written an integration error log.
    private static Boolean errorLogged = false;

    private static Boolean processResponse(
        String responseBody,
        RES_AccountIntegrationService service,
        Id recordId
    ) {
        errorLogged = false;
        if (String.isBlank(responseBody)) {
            return false;
        }

        RES_ResponseWrapper responseWrapper = RES_ResponseWrapper.deserialize(responseBody);
        String errorMessage = '';
        Boolean isSuccess = false;

        if (responseWrapper != null &&
            responseWrapper.responseReturn != null &&
            responseWrapper.responseReturn.item != null) {

            for (RES_ResponseWrapper.ItemWrapper item : responseWrapper.responseReturn.item) {
                if (item.type == 'E' && String.isNotBlank(item.message)) {
                    errorMessage += item.message;
                } else if (item.type == 'S') {
                    isSuccess = true;
                }
            }
        }

        if (String.isNotBlank(errorMessage)) {
            RES_IntegrationErrorLogger log = new RES_IntegrationErrorLogger(
                'Account_Sync',
                '',
                errorMessage,
                JSON.serialize(service.getHeaders()),
                'Account',
                recordId,
                String.valueOf(service.getRequestBody()),
                service.getRequestMethod(),
                'Account_Sync',
                service.getRetryCount(),
                'Client Side'
            );
            RES_ResponseWrapper.logError(log);
            errorLogged = true;
        }

        return isSuccess;
    }

    // Navigates n0:ZRE_SF_BP_CREATEResponse.ET_RESULTS.item and returns the item map, or null.
    private static Map<String, Object> extractResultItem(String responseBody) {
        if (String.isBlank(responseBody)) {
            return null;
        }
        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            Object responseObj = root.get('n0:ZRE_SF_BP_CREATEResponse');
            if (responseObj == null) {
                return null;
            }
            Map<String, Object> etResults = (Map<String, Object>) ((Map<String, Object>) responseObj).get('ET_RESULTS');
            if (etResults == null) {
                return null;
            }
            Object itemObj = etResults.get('item');
            return itemObj != null ? (Map<String, Object>) itemObj : null;
        } catch (Exception e) {
            System.debug('Could not navigate SAP response structure: ' + e.getMessage());
            return null;
        }
    }

    private static String extractBpNumber(String responseBody) {
        try {
            Map<String, Object> item = extractResultItem(responseBody);
            if (item != null && item.containsKey('BP_NUMBER')) {
                String val = String.valueOf(item.get('BP_NUMBER'));
                if (String.isNotBlank(val)) {
                    return val;
                }
            }
        } catch (Exception e) {
            System.debug('Could not extract BP number from response: ' + e.getMessage());
        }
        return null;
    }

    private static String extractAddrNumber(String responseBody) {
        try {
            Map<String, Object> item = extractResultItem(responseBody);
            if (item == null) {
                return null;
            }
            // SAP returns TT_ADDRESS_KEYS as an empty string on failure, so guard the casts.
            Object addrKeysObj = item.get('TT_ADDRESS_KEYS');
            if (!(addrKeysObj instanceof Map<String, Object>)) {
                return null;
            }
            Object addrItemObj = ((Map<String, Object>) addrKeysObj).get('item');
            if (addrItemObj instanceof List<Object>) {
                List<Object> addrItems = (List<Object>) addrItemObj;
                addrItemObj = addrItems.isEmpty() ? null : addrItems[0];
            }
            if (addrItemObj instanceof Map<String, Object>) {
                Object addrNumber = ((Map<String, Object>) addrItemObj).get('ADDRNUMBER');
                if (addrNumber != null && String.isNotBlank(String.valueOf(addrNumber))) {
                    return String.valueOf(addrNumber);
                }
            }
        } catch (Exception e) {
            System.debug('Could not extract ADDRNUMBER from response: ' + e.getMessage());
        }
        return null;
    }

    private static Boolean extractOverallStatus(String responseBody) {
        try {
            Map<String, Object> item = extractResultItem(responseBody);
            if (item != null && item.containsKey('OVERALL_STATUS')) {
                return String.valueOf(item.get('OVERALL_STATUS')) == 'S';
            }
        } catch (Exception e) {
            System.debug('Could not extract OVERALL_STATUS from response: ' + e.getMessage());
        }
        return false;
    }

    // Extracts messages from TT_MESSAGES within ET_RESULTS.item.
    // errorsOnly = true returns only TYPE 'E' messages; false returns the text of every message.
    private static String extractTtMessages(String responseBody, Boolean errorsOnly) {
        try {
            Map<String, Object> item = extractResultItem(responseBody);
            if (item == null) {
                return null;
            }
            Object ttMessages = item.get('TT_MESSAGES');
            if (ttMessages == null || !(ttMessages instanceof Map<String, Object>)) {
                return null;
            }
            Object messagesItemObj = ((Map<String, Object>) ttMessages).get('item');
            if (messagesItemObj == null) {
                return null;
            }
            List<Object> messageList = messagesItemObj instanceof List<Object>
                ? (List<Object>) messagesItemObj
                : new List<Object>{ messagesItemObj };

            String errorMessages = '';
            for (Object msgObj : messageList) {
                Map<String, Object> msg = (Map<String, Object>) msgObj;
                String msgType = msg.containsKey('TYPE') ? String.valueOf(msg.get('TYPE')) : '';
                String msgText = msg.containsKey('MESSAGE') ? String.valueOf(msg.get('MESSAGE')) : '';
                if ((!errorsOnly || msgType == 'E') && String.isNotBlank(msgText)) {
                    errorMessages += msgText + ' ';
                }
            }
            return String.isNotBlank(errorMessages) ? errorMessages.trim() : null;
        } catch (Exception e) {
            System.debug('Could not extract TT_MESSAGES from response: ' + e.getMessage());
            return null;
        }
    }

    // Parses the contact person BP number from TT_MESSAGES for company account insert responses.
    // Looks for a message matching "Contact person BP {number} created and linked".
    private static String extractContactPersonBp(String responseBody) {
        try {
            Map<String, Object> item = extractResultItem(responseBody);
            if (item == null) {
                return null;
            }
            Object ttMessages = item.get('TT_MESSAGES');
            if (ttMessages == null || !(ttMessages instanceof Map<String, Object>)) {
                return null;
            }
            Object messagesItemObj = ((Map<String, Object>) ttMessages).get('item');
            if (messagesItemObj == null) {
                return null;
            }
            List<Object> messageList = messagesItemObj instanceof List<Object>
                ? (List<Object>) messagesItemObj
                : new List<Object>{ messagesItemObj };

            Pattern contactBpPattern = Pattern.compile('Contact person BP (\\d+)');
            for (Object msgObj : messageList) {
                Map<String, Object> msg = (Map<String, Object>) msgObj;
                String message = msg.containsKey('MESSAGE') ? String.valueOf(msg.get('MESSAGE')) : '';
                Matcher m = contactBpPattern.matcher(message);
                if (m.find()) {
                    return m.group(1);
                }
            }
        } catch (Exception e) {
            System.debug('Could not extract contact person BP from response: ' + e.getMessage());
        }
        return null;
    }

    public static void syncAccounts(List<Account> accounts, String requestMethod, String triggerContext) {
        RES_AccountIntegrationService service = new RES_AccountIntegrationService(requestMethod);
        String body = service.hydrateRequestBody(accounts, triggerContext);
        service.setObjectName('Account');
        service.setRequestName('Account_Sync');
        service.setRecordId(String.valueOf(accounts[0].Id));
        service.setBody(body);

        try {
            RES_IntegrationResponse response = service.sendRequest();

            if (response == null) {
                System.debug('Account Integration Service: sendRequest() returned null response.');
                return;
            }

            System.debug(
                'Account Integration Service | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );

            Boolean isSuccess = processResponse(response.responseBody, service, accounts[0].Id)
                || extractOverallStatus(response.responseBody);

            // If processResponse did not log an error (e.g. RES_ResponseWrapper couldn't parse
            // the nested TT_MESSAGES structure), log the failure directly. OVERALL_STATUS != 'S'
            // is a failure even when the HTTP status is 200 and no TYPE 'E' message is present.
            if (!isSuccess && !errorLogged) {
                String ttError = extractTtMessages(response.responseBody, true);
                if (String.isBlank(ttError)) {
                    ttError = extractTtMessages(response.responseBody, false);
                }
                if (String.isBlank(ttError)) {
                    ttError = 'SAP returned OVERALL_STATUS=E';
                }
                RES_IntegrationErrorLogger log = new RES_IntegrationErrorLogger(
                    'Account_Sync',
                    '',
                    ttError,
                    JSON.serialize(service.getHeaders()),
                    'Account',
                    accounts[0].Id,
                    String.valueOf(service.getRequestBody()),
                    service.getRequestMethod(),
                    'Account_Sync',
                    service.getRetryCount(),
                    'Client Side'
                );
                RES_ResponseWrapper.logError(log);
            }

            if (isSuccess) {
                Account toSync = new Account(
                    Id = accounts[0].Id,
                    RES_Last_Sync_DateTime__c = System.now()
                );
                Database.update(toSync, false, AccessLevel.SYSTEM_MODE);
            }

            if (triggerContext == 'I') {
                // Always store BP_NUMBER and ADDRNUMBER when present in the response.
                // SAP may return OVERALL_STATUS=E with a valid BP_NUMBER when the BP already
                // exists (e.g. "External ID - Associated With BP") — the number is still valid
                // and must be persisted so subsequent update calls include it.
                String bpNumber = extractBpNumber(response.responseBody);
                String addrNumber = extractAddrNumber(response.responseBody);
                if (String.isNotBlank(bpNumber) || String.isNotBlank(addrNumber)) {
                    Account toUpdate = new Account(Id = accounts[0].Id);
                    if (String.isNotBlank(bpNumber)) {
                        toUpdate.RES_External_Key__c = bpNumber;
                    }
                    if (String.isNotBlank(addrNumber)) {
                        toUpdate.RES_SAP_ADDR_NUMBER__c = addrNumber;
                    }
                    Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
                }

                // For company account inserts, store the SAP contact person BP on the related contact
                Map<Id, Account> accountsById = new RES_AccountDAOLayer().getAccountsForSyncByIds(new Set<Id>{ accounts[0].Id });
                Account syncedAccount = accountsById.get(accounts[0].Id);
                if (syncedAccount != null && !syncedAccount.IsPersonAccount) {
                    String contactPersonBp = extractContactPersonBp(response.responseBody);
                    if (String.isNotBlank(contactPersonBp)) {
                        Map<Id, List<Contact>> contactsByAccountId = new RES_ContactDAOLayer()
                            .getContactsByAccountIds(new Set<Id>{ accounts[0].Id });
                        List<Contact> relatedContacts = contactsByAccountId.get(accounts[0].Id);
                        if (relatedContacts != null && !relatedContacts.isEmpty()) {
                            Contact firstContact = relatedContacts[0];
                            firstContact.RES_SAP_Contact_Id__c = contactPersonBp;
                            Database.update(firstContact, false, AccessLevel.SYSTEM_MODE);
                        }
                    }
                }
            }

        } catch (Exception e) {
            System.debug('Exception occurred while calling the Account Integration Service: ' + e.getMessage());
        }
    }
}