/**
 * @description
 * Integration service responsible for synchronizing Salesforce Account (Business Partner)
 * records with SAP S/4HANA via the Business Partner API.
 *
 * Extends RES_BaseIntegrationCalloutService to leverage the common integration
 * framework for HTTP callout configuration, retry handling, and response processing.
 *
 * On a successful insert response, the SAP-assigned BP number is stored in
 * DIR_SAP_Business_Partner_ID__c on the Account record.
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

    private static RES_AccountRequestWrapper buildAccountWrapper(Account acc, String triggerContext, List<Contact> relatedContacts) {
        RES_AccountRequestWrapper wrapper = new RES_AccountRequestWrapper();

        Boolean isPersonAccount = acc.IsPersonAccount;
        String recordTypeDeveloperName = acc.RecordType != null ? acc.RecordType.DeveloperName : null;
        Boolean isInsert = triggerContext == 'I';

        wrapper.Id = acc.Id;
        // RecordTypeId: '1' for PersonAccount, '2' for Company
        wrapper.RecordTypeId = (recordTypeDeveloperName == 'PersonAccount') ? '1' : '2';
        wrapper.Type = acc.Type;
        // PersonTitle maps to RES_Corporate_Title__c
        wrapper.PersonTitle = acc.RES_Corporate_Title__c;
        // LastName and Name only for PersonAccount
        wrapper.LastName = isPersonAccount ? acc.LastName : null;
        wrapper.Name = isPersonAccount ? acc.Name : null;
        wrapper.RES_Language = acc.RES_Language__pc;
        wrapper.PersonGenderIdentity = acc.PersonGenderIdentity;
        wrapper.RES_Marital_Status = acc.RES_Marital_Status__pc;
        wrapper.RES_Nationality = acc.RES_Nationality__pc;
        wrapper.RES_Date_of_Birth = acc.RES_Date_of_Birth__pc != null ? String.valueOf(acc.RES_Date_of_Birth__pc) : null;
        wrapper.RES_Company_Additional_Name = ''; // always blank per payload spec
        wrapper.RES_OBJECT_TASK = triggerContext;
        // RES_BP_NUMBER: null on first insert; pass DIR_SAP_Business_Partner_ID__c on update (must not be null)
        wrapper.RES_BP_NUMBER = isInsert ? null : acc.DIR_SAP_Business_Partner_ID__c;
        wrapper.RES_NAME1 = isPersonAccount ? null : acc.FirstName;
        wrapper.RES_NAME2 = isPersonAccount ? null : acc.LastName;
        wrapper.RES_KTOKD = acc.RES_Planning_Group__c;
        wrapper.RES_Relationship_Type = acc.RES_Relationship_Type__c;
        wrapper.Change_Indicator = triggerContext;
        // Fullname: only for Company Account; null for PersonAccount
        wrapper.Fullname = isPersonAccount ? null : acc.Name;
        wrapper.Account_Category = acc.RES_Planning_Group__c;

        if (!isPersonAccount && (String.isNotBlank(acc.RES_Tax_Category__c) || String.isNotBlank(acc.RES_Tax_Number__c))) {
            RES_AccountRequestWrapper.TaxNumbers taxNumbers = new RES_AccountRequestWrapper.TaxNumbers();
            RES_AccountRequestWrapper.TaxItem taxItem = new RES_AccountRequestWrapper.TaxItem();
            taxItem.OBJECT_TASK = triggerContext;
            taxItem.TAXTYPE = acc.RES_Tax_Category__c;
            taxItem.TAXNUMBER = acc.RES_Tax_Number__c;
            taxNumbers.item = taxItem;
            wrapper.TT_TAX_NUMBERS = taxNumbers;
        }

        RES_AccountRequestWrapper.AddressItem addressItem = new RES_AccountRequestWrapper.AddressItem();
        addressItem.OBJECT_TASK = triggerContext;
        // ADDRNUMBER: null on insert; on update pass the stored SAP address number (must not be null)
        addressItem.ADDRNUMBER = isInsert ? null : acc.RES_SAP_ADDR_NUMBER__c;
        addressItem.CITY = acc.BillingCity;
        addressItem.POSTL_COD1 = acc.BillingPostalCode;
        addressItem.STREET = acc.BillingStreet;
        addressItem.COUNTRY = acc.BillingCountryCode;
        // LANGU: PersonAccount uses RES_Language__pc; Company Account uses RES_Language__c
        addressItem.LANGU = acc.RES_Language__pc;

        RES_AccountRequestWrapper.PhoneItem phoneItem = new RES_AccountRequestWrapper.PhoneItem();
        phoneItem.OBJECT_TASK = triggerContext;
        phoneItem.TELEPHONE = acc.Phone;
        phoneItem.EXTENSION = acc.RES_Extension__c != null ? String.valueOf(acc.RES_Extension__c) : null;
        phoneItem.COUNTRY = acc.BillingCountryCode;
        RES_AccountRequestWrapper.Phones phones = new RES_AccountRequestWrapper.Phones();
        phones.item = phoneItem;
        addressItem.TT_PHONES = phones;

        RES_AccountRequestWrapper.FaxItem faxItem = new RES_AccountRequestWrapper.FaxItem();
        faxItem.OBJECT_TASK = triggerContext;
        faxItem.FAX = acc.Fax;
        faxItem.COUNTRY = acc.BillingCountryCode;
        RES_AccountRequestWrapper.Faxes faxes = new RES_AccountRequestWrapper.Faxes();
        faxes.item = faxItem;
        addressItem.TT_FAXES = faxes;

        RES_AccountRequestWrapper.EmailItem emailItem = new RES_AccountRequestWrapper.EmailItem();
        emailItem.OBJECT_TASK = triggerContext;
        emailItem.E_MAIL = acc.PersonEmail;
        RES_AccountRequestWrapper.Emails emails = new RES_AccountRequestWrapper.Emails();
        emails.item = emailItem;
        addressItem.TT_EMAILS = emails;

        RES_AccountRequestWrapper.Addresses addresses = new RES_AccountRequestWrapper.Addresses();
        addresses.item = addressItem;
        wrapper.TT_ADDRESSES = addresses;

        if (String.isNotBlank(acc.RES_BP_Role__c)) {
            RES_AccountRequestWrapper.RoleItem roleItem = new RES_AccountRequestWrapper.RoleItem();
            roleItem.OBJECT_TASK = triggerContext;
            roleItem.DATA_KEY = acc.RES_BP_Role__c;
            RES_AccountRequestWrapper.Roles roles = new RES_AccountRequestWrapper.Roles();
            roles.item = new List<RES_AccountRequestWrapper.RoleItem>{ roleItem };
            wrapper.TT_ROLES = roles;
        }

        if (String.isNotBlank(acc.RES_Company_Code__c)) {
            RES_AccountRequestWrapper.CompanyCodeWrapper ccWrapper = new RES_AccountRequestWrapper.CompanyCodeWrapper();
            ccWrapper.RES_Company_Code = acc.RES_Company_Code__c;
            ccWrapper.RES_Reconciliation_Account = acc.RES_Reconciliation_Account__c;
            ccWrapper.RES_Planning_Group = acc.RES_Planning_Group__c;
            ccWrapper.Company_Code_Change_Indicator = triggerContext;
            wrapper.RES_Company_Codes = new List<RES_AccountRequestWrapper.CompanyCodeWrapper>{ ccWrapper };
        }

        if (String.isNotBlank(acc.RES_Identification_Type__c) || String.isNotBlank(acc.RES_Identification_Number__c)) {
            RES_AccountRequestWrapper.IdentificationItem identItem = new RES_AccountRequestWrapper.IdentificationItem();
            identItem.OBJECT_TASK = triggerContext;
            identItem.IDENTIFICATIONCATEGORY = acc.RES_Identification_Type__c;
            identItem.IDENTIFICATIONNUMBER = acc.RES_Identification_Number__c;
            identItem.IDENTRYDATE = acc.RES_ID_Entry_Date__c != null ? String.valueOf(acc.RES_ID_Entry_Date__c) : null;
            identItem.IDVALIDFROMDATE = acc.RES_ID_Valid_From_Date__c != null ? String.valueOf(acc.RES_ID_Valid_From_Date__c) : null;
            identItem.IDVALIDTODATE = acc.RES_ID_Valid_to_Date__c != null ? String.valueOf(acc.RES_ID_Valid_to_Date__c) : null;
            RES_AccountRequestWrapper.Identifications identifications = new RES_AccountRequestWrapper.Identifications();
            identifications.item = identItem;
            wrapper.TT_IDENTIFICATIONS = identifications;
        }

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

        // Contact person fields — derived from related contacts
        Integer contactCount = (relatedContacts != null) ? relatedContacts.size() : 0;
        Contact firstContact = (contactCount >= 1) ? relatedContacts[0] : null;
        wrapper.CONTACT_PERSON_TASK = triggerContext;
        // CONTACT_PERSON_BP: null on insert; on update must not be null
        wrapper.CONTACT_PERSON_BP = isInsert ? null : acc.DIR_SAP_Business_Partner_ID__c;
        wrapper.HAS_CONTACT_PERSON = (contactCount >= 1) ? 'X' : '';
        wrapper.CONTACT_PERSON_GROUPING = (contactCount >= 1) ? 'Z009' : '';
        wrapper.CONTACT_PERSON_TITLE = (firstContact != null) ? firstContact.Salutation : null;
        wrapper.CONTACT_PERSON_END_DATE = (firstContact != null && firstContact.RES_Contact_Person_End_Date__c != null)
            ? String.valueOf(firstContact.RES_Contact_Person_End_Date__c) : null;

        return wrapper;
    }

    private static List<RES_AccountRequestWrapper.CustomField> buildCustomFields(Account acc, Boolean isPersonAccount) {
        List<RES_AccountRequestWrapper.CustomField> customFields = new List<RES_AccountRequestWrapper.CustomField>();
        // RES_Full_Arabic_Name: PersonAccount uses __pc field; Company Account uses __c field
        customFields.add(new RES_AccountRequestWrapper.CustomField(
            'RES_Full_Arabic_Name',
            isPersonAccount ? acc.RES_Full_Arabic_Name__pc : acc.RES_Full_Arabic_Name__c
        ));
        customFields.add(new RES_AccountRequestWrapper.CustomField('RES_SIMAH_Consent', acc.RES_SIMAH_Consent__c));
        customFields.add(new RES_AccountRequestWrapper.CustomField('RES_VIP_Customer', acc.RES_VIP_Customer__c));
        customFields.add(new RES_AccountRequestWrapper.CustomField('RES_Bank_Customer', acc.RES_Bank_Customer__c));
        customFields.add(new RES_AccountRequestWrapper.CustomField(
            'RES_Consent_Form_Received_Date',
            acc.RES_Consent_Form_Received_Date__c != null ? String.valueOf(acc.RES_Consent_Form_Received_Date__c) : null
        ));
        return customFields;
    }

    public String hydrateRequestBody(List<Account> accounts, String triggerContext) {
        if (accounts == null || accounts.isEmpty()) {
            throw new RES_IntegrationException('No Account records provided for integration.');
        }

        // Query related contacts for all accounts in one SOQL call
        Set<Id> accountIds = new Set<Id>();
        for (Account acc : accounts) {
            accountIds.add(acc.Id);
        }
        Map<Id, List<Contact>> contactsByAccountId = new RES_ContactDAOLayer().getContactsByAccountIds(accountIds);

        List<RES_AccountRequestWrapper> wrappers = new List<RES_AccountRequestWrapper>();
        for (Account acc : accounts) {
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

    private static Boolean processResponse(
        String responseBody,
        RES_AccountIntegrationService service,
        Id recordId
    ) {
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
        }

        return isSuccess;
    }

    private static String extractBpNumber(String responseBody) {
        if (String.isBlank(responseBody)) {
            return null;
        }
        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            for (String key : new List<String>{ 'BPID', 'BP_NUMBER', 'RES_BP_NUMBER', 'BpId' }) {
                if (root.containsKey(key) && root.get(key) != null) {
                    String val = String.valueOf(root.get(key));
                    if (String.isNotBlank(val)) {
                        return val;
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Could not extract BP number from response: ' + e.getMessage());
        }
        return null;
    }

    private static String extractAddrNumber(String responseBody) {
        if (String.isBlank(responseBody)) {
            return null;
        }
        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            if (root.containsKey('ADDRNUMBER') && root.get('ADDRNUMBER') != null) {
                String val = String.valueOf(root.get('ADDRNUMBER'));
                if (String.isNotBlank(val)) {
                    return val;
                }
            }
        } catch (Exception e) {
            System.debug('Could not extract ADDRNUMBER from response: ' + e.getMessage());
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

            System.debug(
                'Account Integration Service | ' +
                'Status Code: ' + response.statusCode +
                ' | Status: ' + response.status +
                ' | Body: ' + response.responseBody
            );

            Boolean isSuccess = processResponse(response.responseBody, service, accounts[0].Id);

            if (isSuccess && triggerContext == 'I') {
                String bpNumber = extractBpNumber(response.responseBody);
                String addrNumber = extractAddrNumber(response.responseBody);
                if (String.isNotBlank(bpNumber) || String.isNotBlank(addrNumber)) {
                    Account toUpdate = new Account(Id = accounts[0].Id);
                    if (String.isNotBlank(bpNumber)) {
                        toUpdate.DIR_SAP_Business_Partner_ID__c = bpNumber;
                    }
                    if (String.isNotBlank(addrNumber)) {
                        toUpdate.RES_SAP_ADDR_NUMBER__c = addrNumber;
                    }
                    Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
                }
            }

        } catch (Exception e) {
            System.debug('Exception occurred while calling the Account Integration Service: ' + e.getMessage());
        }
    }
}