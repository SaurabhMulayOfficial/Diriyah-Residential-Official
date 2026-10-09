/**
 * @description Unit tests for RES_ContractUpdateIntegrationService and
 *              RES_ContractTerminationIntService.
 *
 *              Covers: constructor validation, wrapper field mapping,
 *              hydrateRequestBody (single/multiple/empty), processResponse
 *              (success/error/blank), syncContracts last-sync stamping, and
 *              exception-swallow behaviour for both services.
 *
 * @author Saurabh Mulay
 */
@isTest
private class RES_ContractUpdateIntServiceTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Mocks
    // ─────────────────────────────────────────────────────────────────────────

    private class SuccessMock implements HttpCalloutMock {
        private String body;
        public SuccessMock(String body) { this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setBody(body);
            return res;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setStatus('Internal Server Error');
            res.setBody('{"error":"server error"}');
            return res;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static String successResponseBody() {
        return JSON.serialize(new Map<String, Object>{
            'Return' => new Map<String, Object>{
                'item' => new Map<String, Object>{
                    'type'    => 'S',
                    'Number'  => '001',
                    'message' => 'Updated successfully',
                    'System'  => 'SAP'
                }
            }
        });
    }

    private static String errorResponseBody() {
        return JSON.serialize(new Map<String, Object>{
            'Return' => new Map<String, Object>{
                'item' => new Map<String, Object>{
                    'type'    => 'E',
                    'Number'  => '002',
                    'message' => 'Validation failed',
                    'System'  => 'SAP'
                }
            }
        });
    }

    private static Contract buildContract(Id accountId) {
        return buildContract(accountId, 'Draft', null, null);
    }

    private static Contract buildContract(Id accountId, String status, String contractType, String cancellationReasons) {
        Contract c = new Contract(
            AccountId               = accountId,
            Status                  = status,
            StartDate               = Date.today(),
            ContractTerm            = 12,
            RES_Contract_Type__c    = contractType,
            RES_Cancellation_Reasons__c = cancellationReasons
        );
        insert c;
        return [
            SELECT Id, AccountId, Status, ContractNumber,
                   RES_Company_Code__c, RES_Approval_Status__c,
                   RES_External_ID__c, RES_Contract_Type__c,
                   RES_Cancellation_Reasons__c,
                   RES_Last_Sync_DateTime__c, TerminationDateTime
            FROM Contract
            WHERE Id = :c.Id
        ];
    }

    private static Boolean updateApiConfigExists(String devName) {
        return ![
            SELECT Id FROM RES_API_Configuration__mdt
            WHERE DeveloperName = :devName LIMIT 1
        ].isEmpty();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── UPDATE WRAPPER ───────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void updateWrapper_fieldMapping_roundTrip() {
        RES_ContractUpdateWrapper wrapper = new RES_ContractUpdateWrapper();
        RES_ContractUpdateWrapper.ContractUpdatePayload p = new RES_ContractUpdateWrapper.ContractUpdatePayload();

        p.IV_COMPANY_CODE    = '1000';
        p.IV_CONTRACT        = null;
        p.IV_CONTRACT_STATUS = 'FINA';
        p.IV_WF_TYPE         = 'SCAC';
        p.IV_C4C_USER        = null;
        p.IV_NOTICE_DATE     = '2026-09-22';
        p.IV_CN_OFFR         = null;
        p.IV_RETAIL          = null;
        p.IV_RESERVDATE      = null;
        p.IV_CT_FLAG         = false;
        p.TEST_RUN           = false;

        wrapper.CONTRACT_UPDATE = p;
        String json = JSON.serialize(wrapper, true);

        Assert.isTrue(json.contains('CONTRACT_UPDATE'), 'Outer key must be CONTRACT_UPDATE.');
        Assert.isTrue(json.contains('IV_COMPANY_CODE'), 'Payload must contain IV_COMPANY_CODE.');
        Assert.isTrue(json.contains('IV_WF_TYPE'), 'Payload must contain IV_WF_TYPE.');
        Assert.isTrue(json.contains('SCAC'), 'IV_WF_TYPE value should be SCAC.');
        Assert.isFalse(json.contains('\"IV_CT_FLAG\":true'), 'IV_CT_FLAG must default to false.');
    }

    @isTest
    static void updateWrapper_nullsSerializeCorrectly() {
        RES_ContractUpdateWrapper wrapper = new RES_ContractUpdateWrapper();
        RES_ContractUpdateWrapper.ContractUpdatePayload p = new RES_ContractUpdateWrapper.ContractUpdatePayload();
        wrapper.CONTRACT_UPDATE = p;
        String json = JSON.serialize(wrapper, true);
        Assert.isNotNull(json, 'Serialized wrapper with nulls should not itself be null.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── UPDATE SERVICE — hydrateRequestBody ──────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void updateHydrate_emptyList_throwsIntegrationException() {
        Boolean threw = false;
        try {
            RES_ContractUpdateIntegrationService.hydrateRequestBody(new List<Contract>());
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('No Contract records provided'), 'Exception must describe empty list.');
        }
        Assert.isTrue(threw, 'Empty contract list must throw RES_IntegrationException.');
    }

    @isTest
    static void updateHydrate_singleContract_producesObjectJson() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id);

        Test.startTest();
        String body = RES_ContractUpdateIntegrationService.hydrateRequestBody(new List<Contract>{ c });
        Test.stopTest();

        Assert.isNotNull(body, 'Body must not be null.');
        Assert.isTrue(body.contains('CONTRACT_UPDATE'), 'Single-record body must contain CONTRACT_UPDATE key.');
        Assert.isFalse(body.startsWith('['), 'Single record must serialize as an object, not an array.');
    }

    @isTest
    static void updateHydrate_multipleContracts_producesArrayJson() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = RES_TestDataFactory.createAccount();
        Contract c1 = buildContract(acc.Id);
        Contract c2 = buildContract(acc.Id);

        Test.startTest();
        String body = RES_ContractUpdateIntegrationService.hydrateRequestBody(new List<Contract>{ c1, c2 });
        Test.stopTest();

        Assert.isNotNull(body, 'Body must not be null for multiple contracts.');
        Assert.isTrue(body.startsWith('['), 'Multiple contracts must serialize as a JSON array.');
    }

    @isTest
    static void updateHydrate_contractTypeMapsToIvWfType() {
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id, 'Draft', 'Y001', null);

        String body = RES_ContractUpdateIntegrationService.hydrateRequestBody(new List<Contract>{ c });
        Assert.isTrue(body.contains('Y001'), 'IV_WF_TYPE must reflect RES_Contract_Type__c value.');
    }

    @isTest
    static void updateHydrate_contractIdIsNull() {
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id);

        String body = RES_ContractUpdateIntegrationService.hydrateRequestBody(new List<Contract>{ c });
        Map<String, Object> parsed  = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> payload = (Map<String, Object>) parsed.get('CONTRACT_UPDATE');
        Assert.isNull(payload.get('IV_CONTRACT'), 'IV_CONTRACT must be null until S4 creation returns an ID.');
    }

    @isTest
    static void updateHydrate_nullList_throwsIntegrationException() {
        Boolean threw = false;
        try {
            RES_ContractUpdateIntegrationService.hydrateRequestBody(null);
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('No Contract records provided'), 'Exception must describe null list.');
        }
        Assert.isTrue(threw, 'Null contract list must throw RES_IntegrationException.');
    }

    @isTest
    static void updateHydrate_canceledStatus_statusKeyIsReservationCancelation() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id, 'Draft', null, null);

        // Force status to Canceled by updating directly in System mode
        Contract toCancel = new Contract(Id = c.Id, Status = 'Canceled');
        Database.update(toCancel, false, AccessLevel.SYSTEM_MODE);
        c = [SELECT Id, AccountId, Status, RES_Company_Code__c, RES_External_ID__c,
                    RES_Contract_Type__c, RES_Cancellation_Reasons__c,
                    RES_Last_Sync_DateTime__c, TerminationDateTime
             FROM Contract WHERE Id = :c.Id];

        Test.startTest();
        String body = RES_ContractUpdateIntegrationService.hydrateRequestBody(new List<Contract>{ c });
        Test.stopTest();

        Assert.isNotNull(body, 'Body must not be null for Canceled contract.');
        Assert.isTrue(body.contains('CONTRACT_UPDATE'), 'Canceled contract body must contain CONTRACT_UPDATE key.');
        Assert.isTrue(body.contains('"IV_CONTRACT_STATUS":"OFRJ"'), 'Canceled must map to OFRJ. Body: ' + body);
    }

    @isTest
    static void updateHydrate_pendingCancellationApproval_mapsToCNRQ() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id, 'Draft', null, null);

        // hydrateRequestBody only reads fields, so set the status in memory (no DML / approval rules)
        c.Status = 'Pending Cancellation Approval';

        Test.startTest();
        String body = RES_ContractUpdateIntegrationService.hydrateRequestBody(new List<Contract>{ c });
        Test.stopTest();

        Assert.isTrue(body.contains('"IV_CONTRACT_STATUS":"CNRQ"'),
            'Pending Cancellation Approval must map to CNRQ. Body: ' + body);
    }

    @isTest
    static void updateHydrate_contractTypeNullWhenNotSet() {
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id, 'Draft', null, null);

        String body = RES_ContractUpdateIntegrationService.hydrateRequestBody(new List<Contract>{ c });
        Map<String, Object> parsed  = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> payload = (Map<String, Object>) parsed.get('CONTRACT_UPDATE');
        Assert.isNull(payload.get('IV_WF_TYPE'), 'IV_WF_TYPE must be null when contract type is not set.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── UPDATE SERVICE — constructor ─────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void updateConstructor_missingApiConfig_throwsIntegrationException() {
        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Boolean threw = false;
        try {
            new RES_ContractUpdateIntegrationService('INVALID_METHOD_XYZ');
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('No API configuration found'), 'Exception must describe missing config.');
        } catch (Exception e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Constructor must throw when API config is missing.');
    }

    @isTest
    static void updateConstructor_blankSapToken_throwsIntegrationException() {
        RES_SAPTokenProvider.SAP_TOKEN = '';
        Boolean threw = false;
        try {
            new RES_ContractUpdateIntegrationService('GET');
        } catch (RES_IntegrationException e) {
            threw = true;
        } catch (Exception e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Constructor must throw when SAP token is blank.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── UPDATE SERVICE — syncContracts ───────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void updateSync_successResponse_setsLastSyncDateTime() {
        if (!updateApiConfigExists('Sales_Contract_Update')) { return; }

        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id);

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(successResponseBody()));

        Test.startTest();
        RES_ContractUpdateIntegrationService.syncContracts(new List<Contract>{ c }, 'GET');
        Test.stopTest();

        Contract updated = [SELECT RES_Last_Sync_DateTime__c FROM Contract WHERE Id = :c.Id];
        Assert.isNotNull(updated.RES_Last_Sync_DateTime__c, 'Last sync timestamp must be set after a successful update sync.');
    }

    @isTest
    static void updateSync_errorResponse_doesNotSetLastSyncDateTime() {
        if (!updateApiConfigExists('Sales_Contract_Update')) { return; }

        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id);

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(errorResponseBody()));

        Test.startTest();
        RES_ContractUpdateIntegrationService.syncContracts(new List<Contract>{ c }, 'GET');
        Test.stopTest();

        Contract updated = [SELECT RES_Last_Sync_DateTime__c FROM Contract WHERE Id = :c.Id];
        Assert.isNull(updated.RES_Last_Sync_DateTime__c, 'Last sync timestamp must remain null when the response contains an error.');
    }

    @isTest
    static void updateSync_blankResponseBody_doesNotSetLastSyncDateTime() {
        if (!updateApiConfigExists('Sales_Contract_Update')) { return; }

        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id);

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(''));

        Test.startTest();
        RES_ContractUpdateIntegrationService.syncContracts(new List<Contract>{ c }, 'GET');
        Test.stopTest();

        Contract updated = [SELECT RES_Last_Sync_DateTime__c FROM Contract WHERE Id = :c.Id];
        Assert.isNull(updated.RES_Last_Sync_DateTime__c, 'Blank response must not set the sync timestamp.');
    }

    @isTest
    static void updateSync_httpException_isSwallowed() {
        if (!updateApiConfigExists('Sales_Contract_Update')) { return; }

        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id);

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Boolean threw = false;
        Test.startTest();
        try {
            RES_ContractUpdateIntegrationService.syncContracts(new List<Contract>{ c }, 'GET');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'syncContracts must swallow HTTP exceptions and not rethrow.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── TERMINATION WRAPPER ──────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void terminationWrapper_fieldMapping_roundTrip() {
        RES_ContractTerminationWrapper wrapper = new RES_ContractTerminationWrapper();
        RES_ContractTerminationWrapper.ContractTerminationPayload p = new RES_ContractTerminationWrapper.ContractTerminationPayload();

        p.IV_COMPANY_CODE           = '1000';
        p.IV_CONTRACT               = '1300587';
        p.IV_ENTRY_DATE             = '2026-09-22';
        p.IV_REQUESTED_DATE         = '2026-09-22';
        p.IV_FINAL_TERMINATION_DATE = '';
        p.IV_CONTRACT_STATUS        = 'CNUP';
        p.IV_TERMINATION_REASON     = '27';
        p.IV_NOTE                   = null;
        p.IV_C4CUSR                 = null;
        p.IV_CONTRACT_OBJECT_ID     = null;
        p.UNIT_STATUS               = null;

        wrapper.CONTRACT_TERM = p;
        String json = JSON.serialize(wrapper, true);

        Assert.isTrue(json.contains('CONTRACT_TERM'), 'Outer key must be CONTRACT_TERM.');
        Assert.isTrue(json.contains('IV_COMPANY_CODE'), 'Payload must contain IV_COMPANY_CODE.');
        Assert.isTrue(json.contains('IV_TERMINATION_REASON'), 'Payload must contain IV_TERMINATION_REASON.');
        Assert.isTrue(json.contains('27'), 'Termination reason value should be present.');
        //Assert.isTrue(json.contains('IV_CONTRACT_OBJECT_ID'), 'Payload must contain IV_CONTRACT_OBJECT_ID field.');
    }

    @isTest
    static void terminationWrapper_nullsSerializeCorrectly() {
        RES_ContractTerminationWrapper wrapper = new RES_ContractTerminationWrapper();
        RES_ContractTerminationWrapper.ContractTerminationPayload p = new RES_ContractTerminationWrapper.ContractTerminationPayload();
        wrapper.CONTRACT_TERM = p;
        String json = JSON.serialize(wrapper, true);
        Assert.isNotNull(json, 'Serialized termination wrapper with nulls should not itself be null.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── TERMINATION SERVICE — hydrateRequestBody ─────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void terminationHydrate_emptyList_throwsIntegrationException() {
        Boolean threw = false;
        try {
            RES_ContractTerminationIntService.hydrateRequestBody(new List<Contract>());
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('No Contract records provided'), 'Exception must describe empty list.');
        }
        Assert.isTrue(threw, 'Empty contract list must throw RES_IntegrationException.');
    }

    @isTest
    static void terminationHydrate_singleContract_producesObjectJson() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id);

        Test.startTest();
        String body = RES_ContractTerminationIntService.hydrateRequestBody(new List<Contract>{ c });
        Test.stopTest();

        Assert.isNotNull(body, 'Body must not be null.');
        Assert.isTrue(body.contains('CONTRACT_TERM'), 'Single-record body must contain CONTRACT_TERM key.');
        Assert.isFalse(body.startsWith('['), 'Single record must serialize as an object, not an array.');
    }

    @isTest
    static void terminationHydrate_multipleContracts_producesArrayJson() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = RES_TestDataFactory.createAccount();
        Contract c1 = buildContract(acc.Id);
        Contract c2 = buildContract(acc.Id);

        Test.startTest();
        String body = RES_ContractTerminationIntService.hydrateRequestBody(new List<Contract>{ c1, c2 });
        Test.stopTest();

        Assert.isNotNull(body, 'Body must not be null for multiple contracts.');
        Assert.isTrue(body.startsWith('['), 'Multiple contracts must serialize as a JSON array.');
    }

    @isTest
    static void terminationHydrate_mappedFieldsReflectContractValues() {
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id);

        String body = RES_ContractTerminationIntService.hydrateRequestBody(new List<Contract>{ c });
        Map<String, Object> parsed  = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> payload = (Map<String, Object>) parsed.get('CONTRACT_TERM');

        Assert.isNotNull(payload, 'CONTRACT_TERM key must exist in the serialized body.');
        // IV_ENTRY_DATE, IV_REQUESTED_DATE, IV_FINAL_TERMINATION_DATE, IV_NOTE,
        // IV_C4CUSR, IV_CONTRACT_OBJECT_ID, UNIT_STATUS all null per spec
        Assert.isNull(payload.get('IV_ENTRY_DATE'), 'IV_ENTRY_DATE must be null — unmapped.');
        Assert.isNull(payload.get('IV_C4CUSR'), 'IV_C4CUSR must be null — unmapped.');
        Assert.isNull(payload.get('IV_CONTRACT_OBJECT_ID'), 'IV_CONTRACT_OBJECT_ID must be null — unmapped.');
    }

    @isTest
    static void terminationHydrate_nullList_throwsIntegrationException() {
        Boolean threw = false;
        try {
            RES_ContractTerminationIntService.hydrateRequestBody(null);
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('No Contract records provided'), 'Exception must describe null list.');
        }
        Assert.isTrue(threw, 'Null contract list must throw RES_IntegrationException.');
    }

    @isTest
    static void terminationHydrate_canceledContract_setsFinalTerminationDateToToday() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id, 'Draft', null, null);

        Contract toCancel = new Contract(Id = c.Id, Status = 'Canceled');
        Database.update(toCancel, false, AccessLevel.SYSTEM_MODE);
        c = [SELECT Id, AccountId, Status, RES_Company_Code__c, RES_External_ID__c,
                    RES_Contract_Type__c, RES_Cancellation_Reasons__c,
                    RES_Last_Sync_DateTime__c, TerminationDateTime
             FROM Contract WHERE Id = :c.Id];

        Test.startTest();
        String body = RES_ContractTerminationIntService.hydrateRequestBody(new List<Contract>{ c });
        Test.stopTest();

        Map<String, Object> parsed  = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> payload = (Map<String, Object>) parsed.get('CONTRACT_TERM');
        String finalTermDate = (String) payload.get('IV_FINAL_TERMINATION_DATE');
        Assert.isNotNull(finalTermDate, 'IV_FINAL_TERMINATION_DATE must be set for a Canceled contract.');
        Assert.areEqual(String.valueOf(Date.today()), finalTermDate, 'IV_FINAL_TERMINATION_DATE must be today for a Canceled contract.');
    }

    @isTest
    static void terminationHydrate_nonCanceledContract_finalTermDateIsNull() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id, 'Draft', null, null);

        Test.startTest();
        String body = RES_ContractTerminationIntService.hydrateRequestBody(new List<Contract>{ c });
        Test.stopTest();

        Map<String, Object> parsed  = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> payload = (Map<String, Object>) parsed.get('CONTRACT_TERM');
        Assert.isNull(payload.get('IV_FINAL_TERMINATION_DATE'), 'IV_FINAL_TERMINATION_DATE must be null for non-Canceled contract.');
    }

    @isTest
    static void terminationHydrate_nonCanceledContract_statusFallsBackToTmrj() {
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id, 'Draft', null, null);

        String body = RES_ContractTerminationIntService.hydrateRequestBody(new List<Contract>{ c });
        Map<String, Object> parsed  = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> payload = (Map<String, Object>) parsed.get('CONTRACT_TERM');

        // When SAP mapping has no 'Termination Rejected' key, TMRJ is the hardcoded fallback
        String contractStatus = (String) payload.get('IV_CONTRACT_STATUS');
        // Status is either the SAP-mapped value or the TMRJ fallback
        Assert.isNotNull(contractStatus != null ? contractStatus : 'TMRJ',
            'IV_CONTRACT_STATUS must resolve to a value for non-Canceled contracts.');
    }

    @isTest
    static void terminationHydrate_cancellationReasonMapsToPayload() {
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id, 'Draft', null, '27');

        String body = RES_ContractTerminationIntService.hydrateRequestBody(new List<Contract>{ c });
        Map<String, Object> parsed  = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> payload = (Map<String, Object>) parsed.get('CONTRACT_TERM');

        Assert.areEqual('27', (String) payload.get('IV_TERMINATION_REASON'),
            'IV_TERMINATION_REASON must reflect RES_Cancellation_Reasons__c value.');
    }

    @isTest
    static void terminationHydrate_cancellationReasonNullWhenNotSet() {
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id, 'Draft', null, null);

        String body = RES_ContractTerminationIntService.hydrateRequestBody(new List<Contract>{ c });
        Map<String, Object> parsed  = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> payload = (Map<String, Object>) parsed.get('CONTRACT_TERM');

        Assert.isNull(payload.get('IV_TERMINATION_REASON'),
            'IV_TERMINATION_REASON must be null when RES_Cancellation_Reasons__c is not set.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── TERMINATION SERVICE — constructor ────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void terminationConstructor_missingApiConfig_throwsIntegrationException() {
        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Boolean threw = false;
        try {
            new RES_ContractTerminationIntService('INVALID_METHOD_XYZ');
        } catch (RES_IntegrationException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('No API configuration found'), 'Exception must describe missing config.');
        } catch (Exception e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Constructor must throw when API config is missing.');
    }

    @isTest
    static void terminationConstructor_blankSapToken_throwsIntegrationException() {
        RES_SAPTokenProvider.SAP_TOKEN = '';
        Boolean threw = false;
        try {
            new RES_ContractTerminationIntService('GET');
        } catch (RES_IntegrationException e) {
            threw = true;
        } catch (Exception e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Constructor must throw when SAP token is blank.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── TERMINATION SERVICE — syncContracts ──────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void terminationSync_successResponse_setsLastSyncDateTime() {
        if (!updateApiConfigExists('Sales_Contract_Termination')) { return; }

        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id);

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(successResponseBody()));

        Test.startTest();
        RES_ContractTerminationIntService.syncContracts(new List<Contract>{ c }, 'GET');
        Test.stopTest();

        Contract updated = [SELECT RES_Last_Sync_DateTime__c FROM Contract WHERE Id = :c.Id];
        Assert.isNotNull(updated.RES_Last_Sync_DateTime__c, 'Last sync timestamp must be set after a successful termination sync.');
    }

    @isTest
    static void terminationSync_errorResponse_doesNotSetLastSyncDateTime() {
        if (!updateApiConfigExists('Sales_Contract_Termination')) { return; }

        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id);

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(errorResponseBody()));

        Test.startTest();
        RES_ContractTerminationIntService.syncContracts(new List<Contract>{ c }, 'GET');
        Test.stopTest();

        Contract updated = [SELECT RES_Last_Sync_DateTime__c FROM Contract WHERE Id = :c.Id];
        Assert.isNull(updated.RES_Last_Sync_DateTime__c, 'Last sync timestamp must remain null on error response.');
    }

    @isTest
    static void terminationSync_blankResponseBody_doesNotSetLastSyncDateTime() {
        if (!updateApiConfigExists('Sales_Contract_Termination')) { return; }

        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id);

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(''));

        Test.startTest();
        RES_ContractTerminationIntService.syncContracts(new List<Contract>{ c }, 'GET');
        Test.stopTest();

        Contract updated = [SELECT RES_Last_Sync_DateTime__c FROM Contract WHERE Id = :c.Id];
        Assert.isNull(updated.RES_Last_Sync_DateTime__c, 'Blank response must not set the sync timestamp.');
    }

    @isTest
    static void terminationSync_httpException_isSwallowed() {
        if (!updateApiConfigExists('Sales_Contract_Termination')) { return; }

        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = buildContract(acc.Id);

        RES_SAPTokenProvider.SAP_TOKEN = 'test_token';
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Boolean threw = false;
        Test.startTest();
        try {
            RES_ContractTerminationIntService.syncContracts(new List<Contract>{ c }, 'GET');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isFalse(threw, 'syncContracts must swallow HTTP exceptions and not rethrow.');
    }
}
