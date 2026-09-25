/**
 * @description Service executing HTTP callouts to SAP Business Partner API.
 * @CreatedDate : 23/09/2026
 * @LastModifiedDate : 23/09/2026
 * @Author : Nitin Marathe
 */

public with sharing class RES_AccountIntegrationService extends RES_BaseIntegrationCalloutService {

    public RES_AccountIntegrationService(String requestMethod) {
        super();
        List<RES_API_Configuration__mdt> apiConfigList = new RES_APIConfigurationsDAO().getAPIConfiguration(requestMethod, 'RES_Business_Partner_API');

        if (apiConfigList == null || apiConfigList.isEmpty()) {
            throw new RES_IntegrationException('No API configuration found for RES_Business_Partner_API');
        }

        setEndpoint(apiConfigList[0].RES_Endpoint__c);
        Integer maxRetries = apiConfigList[0].RES_Max_Retries__c != null ? Integer.valueOf(apiConfigList[0].RES_Max_Retries__c) : 3;
        Integer timeout = apiConfigList[0].RES_Callout_Timeout__c != null ? Integer.valueOf(apiConfigList[0].RES_Callout_Timeout__c) : 10000;

        String sapToken = new RES_SAPTokenProvider().getToken();
        if (String.isBlank(sapToken)) {
            throw new RES_IntegrationException('Failed to retrieve SAP authentication token.');
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

    public String hydrateRequestBody(List<Account> accounts) {
        if (accounts == null || accounts.isEmpty()) {
            throw new RES_IntegrationException('No Account records provided for integration.');
        }

        List<RES_AccountRequestWrapper> requestWrappers = new List<RES_AccountRequestWrapper>();

        for (Account acc : accounts) {
            RES_AccountRequestWrapper wrapper = new RES_AccountRequestWrapper();

            // Determine sync mode (Insert vs Update)
            Boolean isExistingInSAP = String.isNotBlank(acc.DIR_SAP_Business_Partner_ID__c);
            String changeIndicator = isExistingInSAP ? 'U' : 'I';

            wrapper.Id = acc.Id;
            wrapper.RecordTypeId = acc.RecordTypeId;
            wrapper.Type = 'Z001';
            wrapper.LastName = acc.LastName != null ? acc.LastName : 'NameField';
            wrapper.Name = acc.Name;
            wrapper.RES_Language = acc.RES_Language__pc != null ? acc.RES_Language__pc : 'E';
            wrapper.Phone = acc.Phone;
            wrapper.PersonGenderIdentity = acc.PersonGenderIdentity;
            wrapper.RES_Marital_Status = acc.RES_Marital_Status__pc;
            wrapper.RES_Nationality = acc.RES_Nationality__pc;
            wrapper.RES_Date_of_Birth = acc.RES_Date_of_Birth__pc != null ? String.valueOf(acc.RES_Date_of_Birth__pc) : null;
            wrapper.RES_Company_Additional_Name = acc.RES_Company_Additional_Name__c != null ? acc.RES_Company_Additional_Name__c : '';
            wrapper.RES_OBJECT_TASK = '';
            wrapper.RES_BP_NUMBER = '';
            wrapper.RES_NAME1 = acc.FirstName != null ? acc.FirstName : 'COMPANY_NAME1';
            wrapper.RES_NAME2 = acc.LastName != null ? acc.LastName : 'COMPANY_NAME2';
            wrapper.RES_KTOKD = acc.DIR_SAP_Business_Partner_ID__c != null ? acc.DIR_SAP_Business_Partner_ID__c : 'Z001';
            wrapper.RES_Relationship_Type = acc.RES_Relationship_Type__c != null ? acc.RES_Relationship_Type__c : 'Primary';
            wrapper.Change_Indicator = changeIndicator;
            wrapper.Fullname = '';
            wrapper.Account_Category = '';

            // Tax Numbers
            RES_AccountRequestWrapper.TaxItem taxItem = new RES_AccountRequestWrapper.TaxItem();
            taxItem.OBJECT_TASK = 'I';
            taxItem.TAXTYPE = 'SA1';
            taxItem.TAXNUMBER = '310123456700003';
            wrapper.TT_TAX_NUMBERS = new RES_AccountRequestWrapper.TaxNumbers();
            wrapper.TT_TAX_NUMBERS.item = taxItem;

            // Address & Contacts
            RES_AccountRequestWrapper.AddressItem addrItem = new RES_AccountRequestWrapper.AddressItem();
            addrItem.OBJECT_TASK = 'D';
            addrItem.ADDRNUMBER = '';
            addrItem.CITY = acc.BillingCity != null ? acc.BillingCity : 'Riyadh';
            addrItem.POSTL_COD1 = acc.BillingPostalCode != null ? acc.BillingPostalCode : '11564';
            addrItem.STREET = acc.BillingStreet != null ? acc.BillingStreet : 'King Fahd Road';
            addrItem.COUNTRY = acc.BillingCountry != null ? acc.BillingCountry : 'SA';
            addrItem.LANGU = 'EN';

            RES_AccountRequestWrapper.PhoneItem phoneItem = new RES_AccountRequestWrapper.PhoneItem();
            phoneItem.OBJECT_TASK = 'I';
            phoneItem.TELEPHONE = acc.Phone != null ? acc.Phone : '966112223334';
            phoneItem.EXTENSION = '102';
            phoneItem.COUNTRY = 'IN';
            addrItem.TT_PHONES = new RES_AccountRequestWrapper.Phones();
            addrItem.TT_PHONES.item = phoneItem;

            RES_AccountRequestWrapper.FaxItem faxItem = new RES_AccountRequestWrapper.FaxItem();
            faxItem.OBJECT_TASK = 'I';
            faxItem.FAX = acc.Fax != null ? acc.Fax : '966112224445';
            faxItem.COUNTRY = 'SA';
            addrItem.TT_FAXES = new RES_AccountRequestWrapper.Faxes();
            addrItem.TT_FAXES.item = faxItem;

            RES_AccountRequestWrapper.EmailItem emailItem = new RES_AccountRequestWrapper.EmailItem();
            emailItem.OBJECT_TASK = 'I';
            emailItem.E_MAIL = acc.PersonEmail != null ? acc.PersonEmail : 'main.user2@domain.com';
            addrItem.TT_EMAILS = new RES_AccountRequestWrapper.Emails();
            addrItem.TT_EMAILS.item = emailItem;

            wrapper.TT_ADDRESSES = new RES_AccountRequestWrapper.Addresses();
            wrapper.TT_ADDRESSES.item = addrItem;

            // Roles
            RES_AccountRequestWrapper.RoleItem role1 = new RES_AccountRequestWrapper.RoleItem();
            role1.OBJECT_TASK = 'D';
            role1.DATA_KEY = 'FLCU01';
            RES_AccountRequestWrapper.RoleItem role2 = new RES_AccountRequestWrapper.RoleItem();
            role2.OBJECT_TASK = 'I';
            role2.DATA_KEY = 'ZTR601';
            wrapper.TT_ROLES = new RES_AccountRequestWrapper.Roles();
            wrapper.TT_ROLES.item = new List<RES_AccountRequestWrapper.RoleItem>{ role1, role2 };

            // Company Codes
            RES_AccountRequestWrapper.CompanyCodeWrapper ccWrap = new RES_AccountRequestWrapper.CompanyCodeWrapper();
            ccWrap.RES_Company_Code = '1001';
            ccWrap.RES_Reconciliation_Account = '11210000';
            ccWrap.RES_Planning_Group = 'PG_RE01';
            ccWrap.Company_Code_Change_Indicator = 'I';
            wrapper.RES_Company_Codes = new List<RES_AccountRequestWrapper.CompanyCodeWrapper>{ ccWrap };

            // Identifications
            RES_AccountRequestWrapper.IdentificationItem idItem = new RES_AccountRequestWrapper.IdentificationItem();
            idItem.OBJECT_TASK = 'I';
            idItem.IDENTIFICATIONCATEGORY = 'PHA001';
            idItem.IDENTIFICATIONNUMBER = '9332157992B';
            idItem.IDENTRYDATE = '2026-08-04';
            idItem.IDVALIDFROMDATE = '2026-01-01';
            idItem.IDVALIDTODATE = '2030-12-31';
            wrapper.TT_IDENTIFICATIONS = new RES_AccountRequestWrapper.Identifications();
            wrapper.TT_IDENTIFICATIONS.item = idItem;

            // TT Company Codes
            RES_AccountRequestWrapper.CompanyCodeItem ccItem1 = new RES_AccountRequestWrapper.CompanyCodeItem();
            ccItem1.OBJECT_TASK = 'I';
            ccItem1.BUKRS = '9000';
            ccItem1.AKONT = '0000153001';
            RES_AccountRequestWrapper.CompanyCodeItem ccItem2 = new RES_AccountRequestWrapper.CompanyCodeItem();
            ccItem2.OBJECT_TASK = 'I';
            ccItem2.BUKRS = '1000';
            ccItem2.AKONT = '0000153001';
            wrapper.TT_COMPANY_CODES = new RES_AccountRequestWrapper.CompanyCodes();
            wrapper.TT_COMPANY_CODES.item = new List<RES_AccountRequestWrapper.CompanyCodeItem>{ ccItem1, ccItem2 };

            // Custom Fields with explicit type alignment for ternary operators
Object simahConsentVal = acc.RES_SIMAH_Consent__c != null ? (Object) acc.RES_SIMAH_Consent__c : true;
Object vipCustomerVal = acc.RES_VIP_Customer__c != null ? (Object) acc.RES_VIP_Customer__c : ' ';
Object bankCustomerVal = acc.RES_Bank_Customer__c != null ? (Object) acc.RES_Bank_Customer__c : true;
Object consentDateVal = acc.RES_Consent_Form_Received_Date__c != null ? (Object) String.valueOf(acc.RES_Consent_Form_Received_Date__c) : '2026-09-15T10:30:00Z';

wrapper.RES_CustomFields = new List<RES_AccountRequestWrapper.CustomField>{
    new RES_AccountRequestWrapper.CustomField('RES_Full_Arabic_Name', acc.RES_Full_Arabic_Name__c),
    new RES_AccountRequestWrapper.CustomField('RES_SIMAH_Consent', simahConsentVal),
    new RES_AccountRequestWrapper.CustomField('RES_VIP_Customer', vipCustomerVal),
    new RES_AccountRequestWrapper.CustomField('RES_Bank_Customer', bankCustomerVal),
    new RES_AccountRequestWrapper.CustomField('RES_Consent_Form_Received_Date', consentDateVal)
};

            // Payload Differences for Person vs Company Account
            if (acc.IsPersonAccount) {
                wrapper.PersonTitle = acc.PersonTitle != null ? acc.PersonTitle : 'Z001';
                wrapper.CONTACT_PERSON_TASK = '';
                wrapper.CONTACT_PERSON_BP = '';
                wrapper.HAS_CONTACT_PERSON = '';
                wrapper.CONTACT_PERSON_GROUPING = '';
                wrapper.CONTACT_PERSON_TITLE = '';
                wrapper.CONTACT_PERSON_END_DATE = '';
            } else {
                wrapper.PersonTitle = 'Z009';
                wrapper.CONTACT_PERSON_TASK = 'I';
                wrapper.CONTACT_PERSON_BP = '';
                wrapper.HAS_CONTACT_PERSON = 'X';
                wrapper.CONTACT_PERSON_GROUPING = '';
                wrapper.CONTACT_PERSON_TITLE = '';
                wrapper.CONTACT_PERSON_END_DATE = '';
            }

            requestWrappers.add(wrapper);
        }

        return requestWrappers.size() == 1 ? JSON.serialize(requestWrappers[0], true) : JSON.serialize(requestWrappers, true);
    }

    public static void syncAccounts(List<Account> accounts, String requestMethod) {
        if (accounts == null || accounts.isEmpty()) {
            return;
        }

        RES_AccountIntegrationService service = new RES_AccountIntegrationService(requestMethod);
        String body = service.hydrateRequestBody(accounts);
        service.setObjectName('Account');
        service.setRequestName('Account_Sync');
        service.setRecordId(String.valueOf(accounts[0].Id));
        service.setBody(body);

        try {
            RES_IntegrationResponse response = service.sendRequest();

            if (response != null && response.statusCode >= 200 && response.statusCode < 300) {
                Account toUpdate = new Account(
                    Id = accounts[0].Id,
                    RES_Last_Sync_DateTime__c = System.now()
                );
                Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            }
        } catch (Exception e) {
            System.debug('Exception during Account Integration Callout: ' + e.getMessage());
        }
    }
}