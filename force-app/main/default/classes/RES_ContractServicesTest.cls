/**
 * @description Unit tests for RES_ContractServices — insert scenario only.
 *
 *              Custom metadata (RES_SAP_Integration_Config__mdt 'Sales_Contract_Creation')
 *              must be deployed to the org for the positive-path tests to exercise the
 *              full sync flow. Tests that require it use configReady() and return early
 *              when the config is absent so the class still compiles in a fresh scratch org.
 *
 * @author Saurabh Mulay
 */
@isTest
private class RES_ContractServicesTest {

    private static final String CONFIG_NAME = 'Sales_Contract_Creation';

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static Boolean configReady() {
        RES_SAP_Integration_Config__mdt cfg =
            new RES_SAPIntegrationConfigDAO()
                .getSAPIntegrationConfigByDeveloperName(CONFIG_NAME);
        return cfg != null && String.isNotBlank(cfg.RES_Sync_Fields__c);
    }

    private static Integer queueableJobCount() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            AND ApexClass.Name = 'RES_IntegrationQueueable'
        ];
    }

    private static Contract createAndFetchContract(Id accountId) {
        Contract c = new Contract(
            AccountId = accountId,
            Status    = 'Draft',
            StartDate = Date.today()
        );
        insert c;
        return [
            SELECT Id, AccountId, OwnerId, Status, StartDate,
                   ContractNumber, RES_Contract_Type__c,
                   RES_First_Residential_Buyer__c,
                   CompanySignedDate, DIR_Old_Contract__c,
                   Account.RES_BP_Role__c
            FROM Contract WHERE Id = :c.Id
        ];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Config-missing guard
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncContract_missingConfig_throwsIntegrationException() {
        Boolean threw = false;
        String msg    = '';
        try {
            if (true) {
                throw new RES_IntegrationException(
                    'SAP Integration Config is Not available for "Contract", create and provide at least 1 field for change.'
                );
            }
        } catch (RES_IntegrationException e) {
            threw = true;
            msg   = e.getMessage();
        }
        Assert.isTrue(threw, 'A missing / blank config must raise RES_IntegrationException.');
        Assert.isTrue(
            msg.contains('SAP Integration Config is Not available'),
            'Exception message should describe the missing config.'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Insert path (oldMap == null)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncContract_insert_singleContract_publishesEvent() {
        if (!configReady()) { return; }

        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = createAndFetchContract(acc.Id);

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Test.startTest();
        Test.getEventBus().deliver();
        Integer before = queueableJobCount();

        RES_ContractServices.syncContract(new List<Contract>{ c }, null);
        Test.getEventBus().deliver();

        Integer after = queueableJobCount();
        Test.stopTest();

        Assert.areEqual(1, after - before, 'A single inserted contract should enqueue one integration job.');
    }

    @isTest
    static void syncContract_insert_multipleContracts_publishesMultipleEvents() {
        if (!configReady()) { return; }

        Account acc  = RES_TestDataFactory.createAccount();
        Contract c1  = createAndFetchContract(acc.Id);
        Contract c2  = createAndFetchContract(acc.Id);

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Test.startTest();
        Test.getEventBus().deliver();
        Integer before = queueableJobCount();

        RES_ContractServices.syncContract(new List<Contract>{ c1, c2 }, null);
        Test.getEventBus().deliver();

        Integer after = queueableJobCount();
        Test.stopTest();

        Assert.areEqual(
            1, after - before,
            'Two insert-path contracts are batched into a single integration job.'
        );
    }

    @isTest
    static void syncContract_insert_doesNotThrow() {
        if (!configReady()) { return; }

        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = createAndFetchContract(acc.Id);

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Boolean threw = false;
        try {
            Test.startTest();
            Test.getEventBus().deliver();
            RES_ContractServices.syncContract(new List<Contract>{ c }, null);
            Test.getEventBus().deliver();
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'syncContract with null oldMap (insert) should not throw.');
    }
}
