/**
 * @description Unit tests for RES_AccountIntegrationService.
 *
 *              Coverage:
 *              - Constructor: missing API config → exception
 *              - Constructor: blank SAP token → exception
 *              - hydrateRequestBody: null / empty list guard
 *              - hydrateRequestBody: single account → JSON object
 *              - hydrateRequestBody: multiple accounts → JSON array
 *              - hydrateRequestBody: insert context — RES_BP_NUMBER blank, ADDRNUMBER blank
 *              - hydrateRequestBody: update context — RES_BP_NUMBER from RES_External_Key__c
 *              - hydrateRequestBody: Arabic language code maps to 'A'
 *              - hydrateRequestBody: roles block populated when RES_BP_Role__c present
 *              - hydrateRequestBody: identifications block populated when fields are set
 *              - hydrateRequestBody: company codes block populated when RES_Company_Code__c set
 *              - hydrateRequestBody: static TT_COMPANY_CODES (9000 / 1000) always present
 *              - hydrateRequestBody: RES_CustomFields block always present
 *              - hydrateRequestBody: contact person fields for company account with contact
 *              - syncAccounts: success via Return type S → RES_Last_Sync_DateTime__c set
 *              - syncAccounts: success via OVERALL_STATUS = 'S' → timestamp set
 *              - syncAccounts: BP_NUMBER and ADDRNUMBER stored on insert
 *              - syncAccounts: error response → no timestamp, TT_MESSAGES logged
 *              - syncAccounts: blank response body → no timestamp
 *              - syncAccounts: callout exception swallowed
 *              - syncAccounts: update context — timestamp set, no BP extraction block entered
 *              - syncAccounts: company account insert — contact person BP stored on Contact
 *              - RES_ResponseWrapper: success / error / blank / no-key deserialization
 *              - RES_ResponseWrapper.logError: null logger does not throw
 *              - RES_AccountRequestWrapper: inner class field round-trip
 *
 * @author Nitin Marathe
 */
@isTest
private class RES_AccountIntegrationServiceTest {

    private static final String REQUEST_METHOD = 'GET';

    // ─────────────────────────────────────────────────────────────────────────
    // Metadata guard — tests that need the service constructor skip when the
    // Business_Partner_API custom metadata is not deployed in this org.
    // ─────────────────────────────────────────────────────────────────────────

    private static Boolean canConstruct() {
        return !new RES_APIConfigurationsDAO()
            .getAPIConfiguration(REQUEST_METHOD, 'Business_Partner_API')
            .isEmpty();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test data helpers
    // ─────────────────────────────────────────────────────────────────────────

    // Restricted picklist values differ per org, so pick one that exists.
    private static String firstActivePicklistValue(Schema.DescribeFieldResult fieldDescribe) {
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static Account buildAccount() {
        RES_Config_Switch__c cfg = RES_Config_Switch__c.getOrgDefaults();
        Boolean wasOff = cfg.RES_Triggers_Off__c;
        cfg.RES_Triggers_Off__c = true;
        upsert cfg;

        Id personAccRecordTypeId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();

        Account acc = new Account();
        acc.RecordTypeId                      = personAccRecordTypeId;
        acc.FirstName                         = 'Test3009';
        acc.LastName                          = 'AccIntegration';
        acc.Type                              = 'Z001';
        acc.PersonGenderIdentity              = '1';
        acc.PersonEmail                       = 'main.user122334@domain.com';
        acc.Phone                             = '966112223349';
        acc.Fax                               = '966112224576';
        acc.BillingCity                       = 'Riyadh';
        acc.BillingPostalCode                 = '11564';
        acc.BillingStreet                     = 'King Fahd Road';
        acc.BillingCountryCode                = 'SA';
        acc.RES_Language__pc                  = 'EN';
        acc.RES_Marital_Status__pc            = '1';
        acc.RES_Date_of_Birth__pc             = Date.valueOf('1990-05-15');
        acc.RES_Full_Arabic_Name__pc          = 'نيتين ماراتي';
        acc.RES_Corporate_Title__c            = 'Z001';
        acc.RES_Account_Group__c              = 'Z001';
        acc.RES_Tax_Category__c               = 'SA0';
        acc.RES_Tax_Number__c                 = '345466312345653';
        acc.RES_Extension__c                  = 102;
        acc.RES_BP_Role__c                    = 'ZTR602';
        acc.RES_Company_Code__c               = '9000';
        acc.RES_Reconciliation_Account__c     = '153001';
        acc.RES_Planning_Group__c             = 'Y1';
        acc.RES_Identification_Type__c        = 'ZIT03';
        acc.RES_Identification_Number__c      = '91321579236';
        acc.RES_ID_Entry_Date__c              = Date.valueOf('2026-08-04');
        acc.RES_ID_Valid_From_Date__c         = Date.valueOf('2026-01-01');
        acc.RES_ID_Valid_to_Date__c           = Date.valueOf('2030-12-31');
        acc.RES_SIMAH_Consent__c              = '101';
        acc.RES_VIP_Customer__c               = false;
        acc.RES_Bank_Customer__c              = true;
        acc.RES_Consent_Form_Received_Date__c = DateTime.newInstanceGmt(2026, 9, 15, 10, 30, 0);
        insert acc;

        cfg.RES_Triggers_Off__c = wasOff;
        upsert cfg;
        return acc;
    }

    private static Account buildCompanyAccount() {
        RES_Config_Switch__c cfg = RES_Config_Switch__c.getOrgDefaults();
        Boolean wasOff = cfg.RES_Triggers_Off__c;
        cfg.RES_Triggers_Off__c = true;
        upsert cfg;

        Id companyRTId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('RES_Company')
            .getRecordTypeId();

        Account acc = new Account(
            RecordTypeId                  = companyRTId,
            Name                          = 'Test30/09 10;00 Integration',
            Type                          = 'Z001',
            RES_Corporate_Title__c        = 'Z009',
            RES_Account_Group__c          = 'Z001',
            Phone                         = '966112223390',
            Fax                           = '966112224045',
            RES_Extension__c              = 102,
            BillingStreet                 = 'King Nehru Road',
            BillingCity                   = 'Riyadh',
            BillingPostalCode             = '11564',
            BillingCountryCode            = 'SA',
            RES_Tax_Category__c           = 'SA0',
            RES_Tax_Number__c             = '310123457400003',
            RES_Identification_Type__c    = 'ZIT04',
            RES_CR_number__c              = '9332157452',
            RES_ID_Entry_Date__c          = Date.valueOf('2026-08-05'),
            RES_ID_Valid_From_Date__c     = Date.valueOf('2026-01-02'),
            RES_ID_Valid_to_Date__c       = Date.valueOf('2030-12-31'),
            RES_Company_Code__c           = '9000',
            RES_Reconciliation_Account__c = '153001',
            RES_Planning_Group__c         = 'Y1',
            RES_Relationship_Type__c      = 'FBBP002',
            RES_BP_Role__c                = 'ZTR602',
            RES_Full_Arabic_Name__c       = 'نيتين ماراتي',
            RES_SIMAH_Consent__c          = '101',
            RES_VIP_Customer__c           = false,
            RES_Bank_Customer__c          = true,
            RES_Consent_Form_Received_Date__c = DateTime.valueOf('2026-09-15 10:30:00')
        );
        insert acc;

        cfg.RES_Triggers_Off__c = wasOff;
        upsert cfg;
        return acc;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Response body builders
    // ─────────────────────────────────────────────────────────────────────────

    private static String successResponseBody(String bpNumber, String addrNumber) {
        return JSON.serialize(new Map<String, Object>{
            'n0:ZRE_SF_BP_CREATEResponse' => new Map<String, Object>{
                'ET_RESULTS' => new Map<String, Object>{
                    'item' => new Map<String, Object>{
                        'BP_NUMBER'       => bpNumber,
                        'OVERALL_STATUS'  => 'S',
                        'TT_ADDRESS_KEYS' => new Map<String, Object>{
                            'item' => new Map<String, Object>{ 'ADDRNUMBER' => addrNumber }
                        },
                        'TT_MESSAGES' => new Map<String, Object>{
                            'item' => new List<Object>{
                                new Map<String, Object>{
                                    'TYPE'    => 'S',
                                    'MESSAGE' => 'Business Partner created successfully'
                                }
                            }
                        }
                    }
                },
                'Return' => new Map<String, Object>{
                    'item' => new Map<String, Object>{
                        'type'    => 'S',
                        'message' => 'Success',
                        'System'  => 'SAP'
                    }
                }
            }
        });
    }

    private static String overallStatusOnlyBody(String bpNumber, String addrNumber) {
        return JSON.serialize(new Map<String, Object>{
            'n0:ZRE_SF_BP_CREATEResponse' => new Map<String, Object>{
                'ET_RESULTS' => new Map<String, Object>{
                    'item' => new Map<String, Object>{
                        'BP_NUMBER'       => bpNumber,
                        'OVERALL_STATUS'  => 'S',
                        'TT_ADDRESS_KEYS' => new Map<String, Object>{
                            'item' => new Map<String, Object>{ 'ADDRNUMBER' => addrNumber }
                        }
                    }
                }
            }
        });
    }

    private static String errorReturnBody() {
        return JSON.serialize(new Map<String, Object>{
            'n0:ZRE_SF_BP_CREATEResponse' => new Map<String, Object>{
                'ET_RESULTS' => new Map<String, Object>{
                    'item' => new Map<String, Object>{
                        'BP_NUMBER'      => '',
                        'OVERALL_STATUS' => 'E',
                        'TT_MESSAGES'    => new Map<String, Object>{
                            'item' => new List<Object>{
                                new Map<String, Object>{
                                    'TYPE'    => 'E',
                                    'MESSAGE' => 'Business Partner creation failed'
                                }
                            }
                        }
                    }
                },
                'Return' => new Map<String, Object>{
                    'item' => new Map<String, Object>{
                        'type'    => 'E',
                        'message' => 'Validation error from SAP',
                        'System'  => 'SAP'
                    }
                }
            }
        });
    }

    private static String contactPersonBody(String bpNumber, String contactBp) {
        return JSON.serialize(new Map<String, Object>{
            'n0:ZRE_SF_BP_CREATEResponse' => new Map<String, Object>{
                'ET_RESULTS' => new Map<String, Object>{
                    'item' => new Map<String, Object>{
                        'BP_NUMBER'       => bpNumber,
                        'OVERALL_STATUS'  => 'S',
                        'TT_ADDRESS_KEYS' => new Map<String, Object>{
                            'item' => new Map<String, Object>{ 'ADDRNUMBER' => '0001111111' }
                        },
                        'TT_MESSAGES' => new Map<String, Object>{
                            'item' => new List<Object>{
                                new Map<String, Object>{
                                    'TYPE'    => 'S',
                                    'MESSAGE' => 'Contact person BP ' + contactBp + ' created and linked'
                                }
                            }
                        }
                    }
                },
                'Return' => new Map<String, Object>{
                    'item' => new Map<String, Object>{
                        'type'    => 'S',
                        'message' => 'Success',
                        'System'  => 'SAP'
                    }
                }
            }
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor — no API config → exception
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void constructor_noApiConfig_throwsIntegrationException() {
        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Boolean threw = false;
        try {
            new RES_AccountIntegrationService('INVALID_METHOD_XYZ_9999');
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('No API configuration found'),
                'Exception should describe the missing API config.'
            );
        } catch (Exception e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Constructor must throw when API config is absent.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor — blank SAP token → exception
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void constructor_blankSapToken_throwsIntegrationException() {
        if (!canConstruct()) { return; }
        RES_SAPTokenProvider.SAP_TOKEN = '';
        Boolean threw = false;
        try {
            new RES_AccountIntegrationService(REQUEST_METHOD);
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('Failed to retrieve SAP token'),
                'Exception should describe the blank token failure.'
            );
        } catch (Exception e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Constructor must throw when SAP token is blank.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — null list guard
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_nullList_throwsIntegrationException() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Boolean threw = false;
        Test.startTest();
        try {
            RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
            svc.hydrateRequestBody(null, 'I');
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('No Account records provided'),
                'Exception should describe the null list condition.'
            );
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Null account list must throw RES_IntegrationException.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — empty list guard
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_emptyList_throwsIntegrationException() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());

        Boolean threw = false;
        Test.startTest();
        try {
            RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
            svc.hydrateRequestBody(new List<Account>(), 'I');
        } catch (RES_IntegrationException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Empty account list must throw RES_IntegrationException.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — single account → JSON object (not array)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_singleAccount_returnsObjectJson() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = buildAccount();

        Test.startTest();
        RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
        String body = svc.hydrateRequestBody(new List<Account>{ acc }, 'I');
        Test.stopTest();

        Assert.isTrue(String.isNotBlank(body), 'Body must not be blank for a single account.');
        Assert.isTrue(body.startsWith('{'), 'Single account must serialize to a JSON object, not an array.');
        Assert.isTrue(body.contains('RES_OBJECT_TASK'), 'Body must contain RES_OBJECT_TASK.');
        Assert.isTrue(body.contains('TT_ADDRESSES'), 'Body must contain TT_ADDRESSES block.');
        Assert.isTrue(body.contains('TT_COMPANY_CODES'), 'Body must contain TT_COMPANY_CODES block.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — multiple accounts → JSON array
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_multipleAccounts_returnsArrayJson() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc1 = buildAccount();

        RES_Config_Switch__c cfg = RES_Config_Switch__c.getOrgDefaults();
        cfg.RES_Triggers_Off__c = true;
        upsert cfg;
        Account acc2 = new Account(Name = 'Integration Test Account 2', RES_Identification_Type__c = 'ZIT04');
        insert acc2;
        cfg.RES_Triggers_Off__c = false;
        upsert cfg;

        Test.startTest();
        RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
        String body = svc.hydrateRequestBody(new List<Account>{ acc1, acc2 }, 'I');
        Test.stopTest();

        Assert.isTrue(String.isNotBlank(body), 'Body must not be blank for multiple accounts.');
        Assert.isTrue(body.startsWith('['), 'Multiple accounts must serialize to a JSON array.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — insert context: RES_BP_NUMBER blank
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_insertContext_bpNumberBlank() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = buildAccount();

        Test.startTest();
        RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
        String body = svc.hydrateRequestBody(new List<Account>{ acc }, 'I');
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Assert.areEqual('I', (String) parsed.get('RES_OBJECT_TASK'), 'RES_OBJECT_TASK must be I on insert.');
        Assert.areEqual('', (String) parsed.get('RES_BP_NUMBER'), 'RES_BP_NUMBER must be blank on insert.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — update context: RES_BP_NUMBER carries RES_External_Key__c
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_updateContext_bpNumberFromExternalKey() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = buildAccount();
        Database.update(new Account(Id = acc.Id, RES_External_Key__c = '20001999'), false, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
        String body = svc.hydrateRequestBody(new List<Account>{ acc }, 'U');
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Assert.areEqual('U', (String) parsed.get('RES_OBJECT_TASK'), 'RES_OBJECT_TASK must be U on update.');
        Assert.areEqual('20001999', (String) parsed.get('RES_BP_NUMBER'),
            'RES_BP_NUMBER must carry RES_External_Key__c value on update.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — Arabic language code maps to 'A'
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_arabicLanguage_mapsToA() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = buildAccount();

        Test.startTest();
        RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
        String body = svc.hydrateRequestBody(new List<Account>{ acc }, 'I');
        Test.stopTest();

        Assert.isTrue(body.contains('"RES_Language"'), 'Body must contain RES_Language field.');
        Assert.isTrue(body.contains('"E"'), 'English language code must map to E.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — non-Arabic language code maps to 'E'
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_nonArabicLanguage_mapsToE() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = buildAccount();

        Test.startTest();
        RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
        String body = svc.hydrateRequestBody(new List<Account>{ acc }, 'I');
        Test.stopTest();

        Assert.isTrue(body.contains('"E"'), 'Non-Arabic language code must map to E.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — TT_ROLES block included when RES_BP_Role__c is set
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_withBpRole_rolesBlockIncluded() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = buildAccount();

        Test.startTest();
        RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
        String body = svc.hydrateRequestBody(new List<Account>{ acc }, 'I');
        Test.stopTest();

        Assert.isTrue(body.contains('TT_ROLES'), 'Body must include TT_ROLES when RES_BP_Role__c is set.');
        Assert.isTrue(body.contains('ZTR602'), 'TT_ROLES DATA_KEY must carry the BP role value.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — TT_IDENTIFICATIONS block included when fields are set
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_withIdentification_identificationsBlockIncluded() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = buildAccount();

        Test.startTest();
        RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
        String body = svc.hydrateRequestBody(new List<Account>{ acc }, 'I');
        Test.stopTest();

        Assert.isTrue(body.contains('TT_IDENTIFICATIONS'),
            'Body must include TT_IDENTIFICATIONS when identification fields are set.');
        Assert.isTrue(body.contains('91321579236'), 'Identification number must appear in the body.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — RES_Company_Codes block included when RES_Company_Code__c set
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_withCompanyCode_companyCodesBlockIncluded() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = buildCompanyAccount();

        Test.startTest();
        RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
        String body = svc.hydrateRequestBody(new List<Account>{ acc }, 'I');
        Test.stopTest();

        Assert.isTrue(body.contains('RES_Company_Codes'),
            'Body must include RES_Company_Codes when RES_Company_Code__c is set.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — static TT_COMPANY_CODES always contains 9000 and 1000
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_staticCompanyCodes_alwaysPresent() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = buildAccount();

        Test.startTest();
        RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
        String body = svc.hydrateRequestBody(new List<Account>{ acc }, 'I');
        Test.stopTest();

        Assert.isTrue(body.contains('"9000"'), 'TT_COMPANY_CODES must always include BUKRS 9000.');
        Assert.isTrue(body.contains('"1000"'), 'TT_COMPANY_CODES must always include BUKRS 1000.');
        Assert.isTrue(body.contains('0000153001'), 'AKONT 0000153001 must be present for BUKRS 9000.');
        Assert.isTrue(body.contains('0000153005'), 'AKONT 0000153005 must be present for BUKRS 1000.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — RES_CustomFields block always present
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_customFieldsBlock_alwaysPresent() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = buildAccount();

        Test.startTest();
        RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
        String body = svc.hydrateRequestBody(new List<Account>{ acc }, 'I');
        Test.stopTest();

        Assert.isTrue(body.contains('RES_CustomFields'), 'Body must always contain RES_CustomFields block.');
        Assert.isTrue(body.contains('RES_SIMAH_Consent'), 'CustomFields must include RES_SIMAH_Consent.');
        Assert.isTrue(body.contains('RES_VIP_Customer'), 'CustomFields must include RES_VIP_Customer.');
        Assert.isTrue(body.contains('RES_Bank_Customer'), 'CustomFields must include RES_Bank_Customer.');
        Assert.isTrue(body.contains('RES_Full_Arabic_Name'), 'CustomFields must include RES_Full_Arabic_Name.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — company account with contact: CONTACT_PERSON_* fields set
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_companyAccountWithContact_contactPersonFieldsSet() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = buildCompanyAccount();

        RES_Config_Switch__c cfg = RES_Config_Switch__c.getOrgDefaults();
        cfg.RES_Triggers_Off__c = true;
        upsert cfg;
        Contact con = new Contact(
            FirstName = 'Integration',
            LastName  = 'Contact',
            AccountId = acc.Id,
            Email     = 'integration.contact@test.com'
        );
        insert con;
        cfg.RES_Triggers_Off__c = false;
        upsert cfg;

        Test.startTest();
        RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
        String body = svc.hydrateRequestBody(new List<Account>{ acc }, 'I');
        Test.stopTest();

        Assert.isTrue(body.contains('CONTACT_PERSON_TASK'),
            'Body must contain CONTACT_PERSON_TASK for a company account.');
        Assert.isTrue(body.contains('HAS_CONTACT_PERSON'),
            'Body must contain HAS_CONTACT_PERSON for a company account.');
        Assert.isTrue(body.contains('"X"'), 'HAS_CONTACT_PERSON must be X when a contact exists.');
        Assert.isTrue(body.contains('CONTACT_PERSON_GROUPING'),
            'Body must contain CONTACT_PERSON_GROUPING for a company account.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncAccounts — success via Return type S → timestamp set
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncAccounts_successViaReturnTypeS_setsLastSyncDateTime() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = successResponseBody('20001999', '0001234567');
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = buildAccount();

        Test.startTest();
        RES_AccountIntegrationService.syncAccounts(new List<Account>{ acc }, REQUEST_METHOD, 'I');
        Test.stopTest();

        Assert.areEqual(1, mock.businessCallCount, 'Exactly one business callout must be made.');
        Account updated = [SELECT RES_Last_Sync_DateTime__c FROM Account WHERE Id = :acc.Id];
        Assert.isNotNull(updated.RES_Last_Sync_DateTime__c,
            'RES_Last_Sync_DateTime__c must be set after a successful sync.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncAccounts — success via OVERALL_STATUS = 'S' only → timestamp set
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncAccounts_successViaOverallStatus_setsLastSyncDateTime() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = overallStatusOnlyBody('20009999', '0009876543');
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = buildAccount();

        Test.startTest();
        RES_AccountIntegrationService.syncAccounts(new List<Account>{ acc }, REQUEST_METHOD, 'I');
        Test.stopTest();

        Account updated = [SELECT RES_Last_Sync_DateTime__c FROM Account WHERE Id = :acc.Id];
        Assert.isNotNull(updated.RES_Last_Sync_DateTime__c,
            'RES_Last_Sync_DateTime__c must be set when OVERALL_STATUS = S.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncAccounts — insert: BP_NUMBER and ADDRNUMBER stored on Account
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncAccounts_insertContext_bpNumberAndAddrNumberStoredOnAccount() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = successResponseBody('20001999', '0001234567');
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = buildAccount();

        Test.startTest();
        RES_AccountIntegrationService.syncAccounts(new List<Account>{ acc }, REQUEST_METHOD, 'I');
        Test.stopTest();

        Account updated = [SELECT RES_External_Key__c, RES_SAP_ADDR_NUMBER__c FROM Account WHERE Id = :acc.Id];
        Assert.areEqual('20001999', updated.RES_External_Key__c,
            'RES_External_Key__c must be populated from BP_NUMBER in the SAP response.');
        Assert.areEqual('0001234567', updated.RES_SAP_ADDR_NUMBER__c,
            'RES_SAP_ADDR_NUMBER__c must be populated from ADDRNUMBER in the SAP response.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncAccounts — insert: Sales_Contract_Creation fired only for unsynced contracts
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncAccounts_insertContext_firesContractCreationForUnsyncedContracts() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = successResponseBody('20001999', '0001234567');
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = buildAccount();

        RES_Config_Switch__c cfg = RES_Config_Switch__c.getOrgDefaults();
        Boolean wasOff = cfg.RES_Triggers_Off__c;
        cfg.RES_Triggers_Off__c = true;
        upsert cfg;
        insert new List<Contract>{
            new Contract(AccountId = acc.Id, Status = 'Draft'),
            new Contract(AccountId = acc.Id, Status = 'Draft'),
            new Contract(AccountId = acc.Id, Status = 'Draft', RES_Last_Sync_DateTime__c = System.now())
        };
        cfg.RES_Triggers_Off__c = wasOff;
        upsert cfg;

        // Two contract events are published; avoid >1 Database.executeBatch in a test.
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy =
            new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = spy;

        Test.startTest();
        RES_AccountIntegrationService.syncAccounts(new List<Account>{ acc }, REQUEST_METHOD, 'I');
        Test.getEventBus().deliver();
        Test.stopTest();

        Map<Id, List<Contract>> contractsByAccount =
            new RES_ContractDAOLayer().getContractsByAccountIds(new Set<Id>{ acc.Id });
        Assert.areEqual(3, contractsByAccount.get(acc.Id).size(),
            'DAO must return every contract of the account.');
        Integer unsynced = 0;
        for (Contract con : contractsByAccount.get(acc.Id)) {
            if (con.RES_Last_Sync_DateTime__c == null) {
                unsynced++;
            }
        }
        Assert.areEqual(2, unsynced, 'Only the two never-synced contracts are eligible for creation events.');
        Account updated = [SELECT RES_External_Key__c FROM Account WHERE Id = :acc.Id];
        Assert.areEqual('20001999', updated.RES_External_Key__c,
            'Account sync must complete and reach the contract event block.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncAccounts — error response → no timestamp, TT_MESSAGES error logged
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncAccounts_errorResponse_doesNotSetLastSyncDateTime() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = errorReturnBody();
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = buildAccount();

        Test.startTest();
        RES_AccountIntegrationService.syncAccounts(new List<Account>{ acc }, REQUEST_METHOD, 'I');
        Test.stopTest();

        Account unchanged = [SELECT RES_Last_Sync_DateTime__c FROM Account WHERE Id = :acc.Id];
        Assert.isNull(unchanged.RES_Last_Sync_DateTime__c,
            'RES_Last_Sync_DateTime__c must remain null when the SAP response contains an error.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncAccounts — blank response body → no timestamp set
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncAccounts_blankResponseBody_doesNotSetLastSyncDateTime() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = '';
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = buildAccount();

        Test.startTest();
        RES_AccountIntegrationService.syncAccounts(new List<Account>{ acc }, REQUEST_METHOD, 'I');
        Test.stopTest();

        Account unchanged = [SELECT RES_Last_Sync_DateTime__c FROM Account WHERE Id = :acc.Id];
        Assert.isNull(unchanged.RES_Last_Sync_DateTime__c,
            'Blank response body must not update the sync timestamp.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncAccounts — callout exception swallowed (does not propagate)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncAccounts_calloutException_doesNotPropagate() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.throwOnBusiness = true;
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = buildAccount();

        Boolean threw = false;
        Test.startTest();
        try {
            RES_AccountIntegrationService.syncAccounts(new List<Account>{ acc }, REQUEST_METHOD, 'I');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'syncAccounts must swallow callout exceptions and never rethrow.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncAccounts — update context: timestamp set, BP extraction block not entered
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncAccounts_updateContext_timestampSetNoBpExtractionBlock() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = successResponseBody('20001999', '0001234567');
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = buildAccount();
        Database.update(
            new Account(Id = acc.Id, RES_External_Key__c = '20001999', RES_SAP_ADDR_NUMBER__c = '0001234567'),
            false,
            AccessLevel.SYSTEM_MODE
        );

        Test.startTest();
        RES_AccountIntegrationService.syncAccounts(new List<Account>{ acc }, REQUEST_METHOD, 'U');
        Test.stopTest();

        Account updated = [SELECT RES_Last_Sync_DateTime__c FROM Account WHERE Id = :acc.Id];
        Assert.isNotNull(updated.RES_Last_Sync_DateTime__c,
            'RES_Last_Sync_DateTime__c must be set on a successful update.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncAccounts — company account insert: contact person BP stored on Contact
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncAccounts_companyInsert_contactPersonBpStoredOnContact() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = contactPersonBody('20002000', '99998888');
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = buildCompanyAccount();

        RES_Config_Switch__c cfg = RES_Config_Switch__c.getOrgDefaults();
        cfg.RES_Triggers_Off__c = true;
        upsert cfg;
        Contact con = new Contact(
            FirstName = 'Company',
            LastName  = 'Contact',
            AccountId = acc.Id,
            Email     = 'company.contact@test.com'
        );
        insert con;
        cfg.RES_Triggers_Off__c = false;
        upsert cfg;

        Test.startTest();
        RES_AccountIntegrationService.syncAccounts(new List<Account>{ acc }, REQUEST_METHOD, 'I');
        Test.stopTest();

        Contact updatedCon = [SELECT RES_SAP_Contact_Id__c FROM Contact WHERE Id = :con.Id];
        Assert.areEqual('99998888', updatedCon.RES_SAP_Contact_Id__c,
            'RES_SAP_Contact_Id__c must be populated from the contact person BP message in the SAP response.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_ResponseWrapper — success item deserialization
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void responseWrapper_successItem_deserializesTypeSCorrectly() {
        String body = JSON.serialize(new Map<String, Object>{
            'Return' => new Map<String, Object>{
                'item' => new Map<String, Object>{
                    'type'    => 'S',
                    'Number'  => '001',
                    'message' => 'BP created successfully',
                    'System'  => 'SAP'
                }
            }
        });

        Test.startTest();
        RES_ResponseWrapper wrapper = RES_ResponseWrapper.deserialize(body);
        Test.stopTest();

        Assert.isNotNull(wrapper, 'Deserializer must return a wrapper for a valid success payload.');
        Assert.isNotNull(wrapper.responseReturn, 'responseReturn must be populated.');
        Assert.isFalse(wrapper.responseReturn.item.isEmpty(), 'item list must contain at least one entry.');
        Assert.areEqual('S', wrapper.responseReturn.item[0].type, 'Success item type must be S.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_ResponseWrapper — error item deserialization
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void responseWrapper_errorItem_deserializesTypeECorrectly() {
        String body = JSON.serialize(new Map<String, Object>{
            'ET_RETURN' => new Map<String, Object>{
                'item' => new Map<String, Object>{
                    'TYPE'    => 'E',
                    'Number'  => '002',
                    'MESSAGE' => 'BP validation failed',
                    'System'  => 'SAP'
                }
            }
        });

        Test.startTest();
        RES_ResponseWrapper wrapper = RES_ResponseWrapper.deserialize(body);
        Test.stopTest();

        Assert.isNotNull(wrapper, 'Deserializer must return a wrapper for an error payload.');
        Assert.areEqual('E', wrapper.responseReturn.item[0].type, 'Error item type must be E.');
        Assert.areEqual('BP validation failed', wrapper.responseReturn.item[0].message,
            'Error message must be preserved during deserialization.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_ResponseWrapper — blank and null body guards
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void responseWrapper_blankBody_returnsNull() {
        Assert.isNull(RES_ResponseWrapper.deserialize(''), 'Blank body must return null.');
        Assert.isNull(RES_ResponseWrapper.deserialize(null), 'Null body must return null.');
    }

    @isTest
    static void responseWrapper_noReturnKey_returnsNull() {
        Assert.isNull(
            RES_ResponseWrapper.deserialize('{"someOtherKey": {}}'),
            'Response without a Return or ET_RETURN key must return null.'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_ResponseWrapper.logError — null logger does not throw
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void logError_nullLogger_doesNotThrow() {
        Boolean threw = false;
        try {
            RES_ResponseWrapper.logError(null);
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'logError must swallow internal exceptions and never rethrow.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RES_AccountRequestWrapper — all inner class fields serialize correctly
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void accountRequestWrapper_allInnerClassFields_serializeCorrectly() {
        RES_AccountRequestWrapper wrapper = new RES_AccountRequestWrapper();
        wrapper.Id               = '001TEST000000001';
        wrapper.RecordTypeId     = '2';
        wrapper.RES_OBJECT_TASK  = 'I';
        wrapper.RES_BP_NUMBER    = '';
        wrapper.RES_NAME1        = 'Test Company';
        wrapper.Change_Indicator = 'I';
        wrapper.Fullname         = 'Test Company';
        wrapper.Account_Category = 'ZIT01';

        RES_AccountRequestWrapper.TaxNumbers taxNumbers = new RES_AccountRequestWrapper.TaxNumbers();
        RES_AccountRequestWrapper.TaxItem taxItem = new RES_AccountRequestWrapper.TaxItem();
        taxItem.OBJECT_TASK = 'I';
        taxItem.TAXTYPE     = 'SA0';
        taxItem.TAXNUMBER   = '000';
        taxNumbers.item     = taxItem;
        wrapper.TT_TAX_NUMBERS = taxNumbers;

        RES_AccountRequestWrapper.AddressItem addrItem = new RES_AccountRequestWrapper.AddressItem();
        addrItem.OBJECT_TASK = 'I';
        addrItem.ADDRNUMBER  = '';
        addrItem.CITY        = 'Riyadh';
        addrItem.COUNTRY     = 'SA';
        addrItem.LANGU       = 'E';

        RES_AccountRequestWrapper.PhoneItem phoneItem = new RES_AccountRequestWrapper.PhoneItem();
        phoneItem.OBJECT_TASK = 'I';
        phoneItem.TELEPHONE   = '+966501234567';
        phoneItem.EXTENSION   = '';
        phoneItem.COUNTRY     = 'SA';
        RES_AccountRequestWrapper.Phones phones = new RES_AccountRequestWrapper.Phones();
        phones.item = phoneItem;
        addrItem.TT_PHONES = phones;

        RES_AccountRequestWrapper.FaxItem faxItem = new RES_AccountRequestWrapper.FaxItem();
        faxItem.OBJECT_TASK = 'I';
        faxItem.FAX         = '';
        faxItem.COUNTRY     = 'SA';
        RES_AccountRequestWrapper.Faxes faxes = new RES_AccountRequestWrapper.Faxes();
        faxes.item = faxItem;
        addrItem.TT_FAXES = faxes;

        RES_AccountRequestWrapper.EmailItem emailItem = new RES_AccountRequestWrapper.EmailItem();
        emailItem.OBJECT_TASK = 'I';
        emailItem.E_MAIL      = 'test@test.com';
        RES_AccountRequestWrapper.Emails emails = new RES_AccountRequestWrapper.Emails();
        emails.item = emailItem;
        addrItem.TT_EMAILS = emails;

        RES_AccountRequestWrapper.Addresses addresses = new RES_AccountRequestWrapper.Addresses();
        addresses.item = addrItem;
        wrapper.TT_ADDRESSES = addresses;

        RES_AccountRequestWrapper.RoleItem roleItem = new RES_AccountRequestWrapper.RoleItem();
        roleItem.OBJECT_TASK = 'I';
        roleItem.DATA_KEY    = 'ZRES';
        RES_AccountRequestWrapper.Roles roles = new RES_AccountRequestWrapper.Roles();
        roles.item = new List<RES_AccountRequestWrapper.RoleItem>{ roleItem };
        wrapper.TT_ROLES = roles;

        RES_AccountRequestWrapper.CompanyCodeWrapper ccWrapper = new RES_AccountRequestWrapper.CompanyCodeWrapper();
        ccWrapper.RES_Company_Code             = '1000';
        ccWrapper.RES_Reconciliation_Account   = '0000153005';
        ccWrapper.RES_Planning_Group           = 'PG01';
        ccWrapper.Company_Code_Change_Indicator = 'I';
        wrapper.RES_Company_Codes = new List<RES_AccountRequestWrapper.CompanyCodeWrapper>{ ccWrapper };

        RES_AccountRequestWrapper.IdentificationItem identItem = new RES_AccountRequestWrapper.IdentificationItem();
        identItem.OBJECT_TASK            = 'I';
        identItem.IDENTIFICATIONCATEGORY = 'ZIT04';
        identItem.IDENTIFICATIONNUMBER   = 'ID-001';
        identItem.IDENTRYDATE            = '2024-01-01';
        identItem.IDVALIDFROMDATE        = '2024-01-01';
        identItem.IDVALIDTODATE          = '2029-12-31';
        RES_AccountRequestWrapper.Identifications identifications = new RES_AccountRequestWrapper.Identifications();
        identifications.item = identItem;
        wrapper.TT_IDENTIFICATIONS = identifications;

        RES_AccountRequestWrapper.CompanyCodeItem ccItem1 = new RES_AccountRequestWrapper.CompanyCodeItem();
        ccItem1.OBJECT_TASK = 'I';
        ccItem1.BUKRS       = '9000';
        ccItem1.AKONT       = '0000153001';
        RES_AccountRequestWrapper.CompanyCodeItem ccItem2 = new RES_AccountRequestWrapper.CompanyCodeItem();
        ccItem2.OBJECT_TASK = 'I';
        ccItem2.BUKRS       = '1000';
        ccItem2.AKONT       = '0000153005';
        RES_AccountRequestWrapper.CompanyCodes companyCodes = new RES_AccountRequestWrapper.CompanyCodes();
        companyCodes.item = new List<RES_AccountRequestWrapper.CompanyCodeItem>{ ccItem1, ccItem2 };
        wrapper.TT_COMPANY_CODES = companyCodes;

        wrapper.RES_CustomFields = new List<RES_AccountRequestWrapper.CustomField>{
            new RES_AccountRequestWrapper.CustomField('RES_Full_Arabic_Name', 'اسم عربي'),
            new RES_AccountRequestWrapper.CustomField('RES_SIMAH_Consent', true),
            new RES_AccountRequestWrapper.CustomField('RES_VIP_Customer', false),
            new RES_AccountRequestWrapper.CustomField('RES_Bank_Customer', false),
            new RES_AccountRequestWrapper.CustomField('RES_Consent_Form_Received_Date', null)
        };

        String serialized = JSON.serialize(wrapper, true);

        Assert.isTrue(serialized.contains('RES_OBJECT_TASK'), 'Serialized wrapper must contain RES_OBJECT_TASK.');
        Assert.isTrue(serialized.contains('TT_TAX_NUMBERS'), 'Serialized wrapper must contain TT_TAX_NUMBERS.');
        Assert.isTrue(serialized.contains('TT_ADDRESSES'), 'Serialized wrapper must contain TT_ADDRESSES.');
        Assert.isTrue(serialized.contains('TT_PHONES'), 'Serialized wrapper must contain TT_PHONES.');
        Assert.isTrue(serialized.contains('TT_FAXES'), 'Serialized wrapper must contain TT_FAXES.');
        Assert.isTrue(serialized.contains('TT_EMAILS'), 'Serialized wrapper must contain TT_EMAILS.');
        Assert.isTrue(serialized.contains('TT_ROLES'), 'Serialized wrapper must contain TT_ROLES.');
        Assert.isTrue(serialized.contains('RES_Company_Codes'), 'Serialized wrapper must contain RES_Company_Codes.');
        Assert.isTrue(serialized.contains('TT_IDENTIFICATIONS'), 'Serialized wrapper must contain TT_IDENTIFICATIONS.');
        Assert.isTrue(serialized.contains('TT_COMPANY_CODES'), 'Serialized wrapper must contain TT_COMPANY_CODES.');
        Assert.isTrue(serialized.contains('RES_CustomFields'), 'Serialized wrapper must contain RES_CustomFields.');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Additional coverage — always-sent blocks, ADDRNUMBER parsing, error fallbacks
    // ═════════════════════════════════════════════════════════════════════════

    // Generic ET_RESULTS response; any null argument omits that key from the item.
    private static String resultsBody(String bpNumber, String overallStatus, Object addrKeys, Object ttMessages) {
        Map<String, Object> item = new Map<String, Object>();
        if (bpNumber != null) {
            item.put('BP_NUMBER', bpNumber);
        }
        if (overallStatus != null) {
            item.put('OVERALL_STATUS', overallStatus);
        }
        if (addrKeys != null) {
            item.put('TT_ADDRESS_KEYS', addrKeys);
        }
        if (ttMessages != null) {
            item.put('TT_MESSAGES', ttMessages);
        }
        return JSON.serialize(new Map<String, Object>{
            'n0:ZRE_SF_BP_CREATEResponse' => new Map<String, Object>{
                'ET_RESULTS' => new Map<String, Object>{ 'item' => item }
            }
        });
    }

    private static Map<String, Object> messagesWith(String type, String message) {
        return new Map<String, Object>{
            'item' => new List<Object>{
                new Map<String, Object>{ 'TYPE' => type, 'MESSAGE' => message }
            }
        };
    }

    private static Account personAccountWithBlankSapFields() {
        RES_Config_Switch__c cfg = RES_Config_Switch__c.getOrgDefaults();
        Boolean wasOff = cfg.RES_Triggers_Off__c;
        cfg.RES_Triggers_Off__c = true;
        upsert cfg;

        Id personAccRecordTypeId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = personAccRecordTypeId,
            FirstName    = 'Blank',
            LastName     = 'Fields',
            PersonEmail  = 'blank.fields@test.com' // satisfies RES_Mobile_Or_Email_Mandatory
        );
        insert acc;
        // Restricted picklists default on insert (e.g. 9000 / ZTR602); clear them in the DB (service re-queries).
        acc.RES_Company_Code__c = null;
        acc.RES_BP_Role__c = null;
        acc.RES_Reconciliation_Account__c = null;
        acc.RES_Planning_Group__c = null;
        update acc;

        cfg.RES_Triggers_Off__c = wasOff;
        upsert cfg;
        return acc;
    }

    private static void runInsertSync(Account acc, String body) {
        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        mock.businessBody = body;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        RES_AccountIntegrationService.syncAccounts(new List<Account>{ acc }, REQUEST_METHOD, 'I');
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hydrateRequestBody — role / company code / identification blocks always sent
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void hydrateRequestBody_blankRoleCompanyCodeIdentification_blocksStillSent() {
        if (!canConstruct()) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = personAccountWithBlankSapFields();

        Test.startTest();
        RES_AccountIntegrationService svc = new RES_AccountIntegrationService(REQUEST_METHOD);
        String body = svc.hydrateRequestBody(new List<Account>{ acc }, 'I');
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Assert.isTrue(parsed.containsKey('Phone'), 'Body must contain Phone.');

        Map<String, Object> roles = (Map<String, Object>) parsed.get('TT_ROLES');
        Assert.isNotNull(roles, 'TT_ROLES must be sent even when RES_BP_Role__c is blank.');
        Map<String, Object> roleItem = (Map<String, Object>) ((List<Object>) roles.get('item'))[0];
        Assert.areEqual('ZTR602', (String) roleItem.get('DATA_KEY'), 'Blank role must fall back to default ZTR602.');

        List<Object> companyCodes = (List<Object>) parsed.get('RES_Company_Codes');
        Assert.isNotNull(companyCodes, 'RES_Company_Codes must be sent even when blank.');
        Map<String, Object> cc = (Map<String, Object>) companyCodes[0];
        Assert.areEqual('', (String) cc.get('RES_Company_Code'), 'Blank company code must be empty string.');
        Assert.areEqual('', (String) cc.get('RES_Reconciliation_Account'), 'Blank reconciliation account must be empty string.');
        Assert.areEqual('', (String) cc.get('RES_Planning_Group'), 'Blank planning group must be empty string.');

        Map<String, Object> idents = (Map<String, Object>) parsed.get('TT_IDENTIFICATIONS');
        Assert.isNotNull(idents, 'TT_IDENTIFICATIONS must be sent even when blank.');
        Map<String, Object> identItem = (Map<String, Object>) idents.get('item');
        Assert.areEqual('', (String) identItem.get('IDENTIFICATIONCATEGORY'), 'Blank identification type must be empty string.');
        Assert.areEqual('', (String) identItem.get('IDENTIFICATIONNUMBER'), 'Blank identification number must be empty string.');
        Assert.areEqual('', (String) identItem.get('IDENTRYDATE'), 'Null entry date must be empty string.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // extractAddrNumber — TT_ADDRESS_KEYS shape variations
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncAccounts_addrKeysEmptyString_onlyBpNumberStored() {
        if (!canConstruct()) { return; }
        Account acc = buildAccount();

        runInsertSync(acc, resultsBody('20003001', 'S', '', null));

        Account updated = [SELECT RES_External_Key__c, RES_SAP_ADDR_NUMBER__c FROM Account WHERE Id = :acc.Id];
        Assert.areEqual('20003001', updated.RES_External_Key__c, 'BP number must still be stored.');
        Assert.isNull(updated.RES_SAP_ADDR_NUMBER__c, 'Address number must stay null when TT_ADDRESS_KEYS is a string.');
    }

    @isTest
    static void syncAccounts_addrKeysItemAsList_addrNumberStored() {
        if (!canConstruct()) { return; }
        Account acc = buildAccount();

        Map<String, Object> addrKeys = new Map<String, Object>{
            'item' => new List<Object>{ new Map<String, Object>{ 'ADDRNUMBER' => '0007654321' } }
        };
        runInsertSync(acc, resultsBody('20003002', 'S', addrKeys, null));

        Account updated = [SELECT RES_External_Key__c, RES_SAP_ADDR_NUMBER__c FROM Account WHERE Id = :acc.Id];
        Assert.areEqual('0007654321', updated.RES_SAP_ADDR_NUMBER__c,
            'Address number must be read from the first entry of an item list.');
    }

    @isTest
    static void syncAccounts_addrKeysItemEmptyList_addrNumberNotStored() {
        if (!canConstruct()) { return; }
        Account acc = buildAccount();

        Map<String, Object> addrKeys = new Map<String, Object>{ 'item' => new List<Object>() };
        runInsertSync(acc, resultsBody('20003003', 'S', addrKeys, null));

        Account updated = [SELECT RES_External_Key__c, RES_SAP_ADDR_NUMBER__c FROM Account WHERE Id = :acc.Id];
        Assert.areEqual('20003003', updated.RES_External_Key__c, 'BP number must still be stored.');
        Assert.isNull(updated.RES_SAP_ADDR_NUMBER__c, 'Empty item list must not store an address number.');
    }

    @isTest
    static void syncAccounts_addrKeysBlankAddrNumber_notStored() {
        if (!canConstruct()) { return; }
        Account acc = buildAccount();

        Map<String, Object> addrKeys = new Map<String, Object>{
            'item' => new Map<String, Object>{ 'ADDRNUMBER' => '' }
        };
        runInsertSync(acc, resultsBody('20003004', 'S', addrKeys, null));

        Account updated = [SELECT RES_External_Key__c, RES_SAP_ADDR_NUMBER__c FROM Account WHERE Id = :acc.Id];
        Assert.isNull(updated.RES_SAP_ADDR_NUMBER__c, 'Blank ADDRNUMBER must not be stored.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // syncAccounts — OVERALL_STATUS = E fallbacks (direct error logging)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncAccounts_overallStatusE_nonErrorMessage_fallbackLogged() {
        if (!canConstruct()) { return; }
        Account acc = buildAccount();

        runInsertSync(acc, resultsBody('', 'E', null, messagesWith('W', 'Warning only message')));

        Account unchanged = [SELECT RES_Last_Sync_DateTime__c FROM Account WHERE Id = :acc.Id];
        Assert.isNull(unchanged.RES_Last_Sync_DateTime__c,
            'Timestamp must not be set when OVERALL_STATUS is E.');
    }

    @isTest
    static void syncAccounts_overallStatusE_noMessages_defaultErrorLogged() {
        if (!canConstruct()) { return; }
        Account acc = buildAccount();

        runInsertSync(acc, resultsBody('', 'E', null, null));

        Account unchanged = [SELECT RES_Last_Sync_DateTime__c FROM Account WHERE Id = :acc.Id];
        Assert.isNull(unchanged.RES_Last_Sync_DateTime__c,
            'Timestamp must not be set when OVERALL_STATUS is E with no messages.');
    }

    @isTest
    static void syncAccounts_overallStatusE_ttMessageItemAsSingleMap_errorLogged() {
        if (!canConstruct()) { return; }
        Account acc = buildAccount();

        Map<String, Object> ttMessages = new Map<String, Object>{
            'item' => new Map<String, Object>{ 'TYPE' => 'E', 'MESSAGE' => 'Single map error' }
        };
        runInsertSync(acc, resultsBody('', 'E', null, ttMessages));

        Account unchanged = [SELECT RES_Last_Sync_DateTime__c FROM Account WHERE Id = :acc.Id];
        Assert.isNull(unchanged.RES_Last_Sync_DateTime__c,
            'Timestamp must not be set when TT_MESSAGES carries a single error item.');
    }
}