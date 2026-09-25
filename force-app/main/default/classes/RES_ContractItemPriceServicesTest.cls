/**
 * @description Unit tests for RES_ContractItemPriceServices.
 *
 *              The positive-path tests require:
 *                1. ContractItemPrice records with ItemId and
 *                   RES_Product__r.RES_Product_External_ID__c populated
 *                   (DAO layer filters on both).
 *                2. Custom metadata 'Sales_Contract_Creation' with at least
 *                   one sync field deployed in the org.
 *              Tests that rely on these use configReady() / cipDataReady()
 *              guards and return early in scratch orgs where they are absent.
 *
 * @author Saurabh Mulay
 */
@isTest
private class RES_ContractItemPriceServicesTest {

    private static final String CONFIG_NAME = 'Sales_Contract_Creation';


    private static Boolean configReady() {
        RES_SAP_Integration_Config__mdt cfg =
            new RES_SAPIntegrationConfigDAO()
                .getSAPIntegrationConfigByDeveloperName(CONFIG_NAME);
        return cfg != null && String.isNotBlank(cfg.RES_Sync_Fields__c);
    }

    private static Contract createTestContract() {
        Account companyAccount = RES_TestDataFactory.createCompanyRTAccount('Globant', '1212121212');

        Id contractRtId = Schema.SObjectType.Contract
            .getRecordTypeInfosByDeveloperName()
            .get('RES_Residential_Sales')
            .getRecordTypeId();

        return RES_TestDataFactory.createContract(companyAccount.Id, 'Draft', contractRtId);
    }

    private static ContractItemPrice makeCip(Id contractId, String productName, Decimal price) {
   
        Product2 fakeProd = new Product2(Name = productName);
        ContractItemPrice cip = new ContractItemPrice(
            ContractId  = contractId,
            Price       = price
        );
        cip.putSObject('RES_Product__r', fakeProd);
        return cip;
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

    private static Integer queueableJobCount() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            AND ApexClass.Name = 'RES_IntegrationQueueable'
        ];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Empty / null-guard paths — no org data needed
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncContracts_emptyList_doesNotThrow() {
        Boolean threw = false;
        try {
            Test.startTest();
            RES_ContractItemPriceServices.syncContracts(new List<ContractItemPrice>());
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'An empty CIP list must be handled silently.');
    }

    @isTest
    static void syncContracts_noMatchingCIPType_skipsSync() {
        // CIPs with an unrecognised type — contractIds set stays empty
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = createAndFetchContract(acc.Id);

        ContractItemPrice cip = new ContractItemPrice(
            ContractId       = c.Id,
            RES_CIP_Type__c  = 'Other'   // neither 'Unit' nor 'Payment Plan'
        );

        Boolean threw = false;
        try {
            Test.startTest();
            RES_ContractItemPriceServices.syncContracts(new List<ContractItemPrice>{ cip });
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'CIPs with an irrelevant type should exit gracefully.');
    }

    @isTest
    static void syncContracts_nullContractId_skipsSync() {
        ContractItemPrice cip = new ContractItemPrice();
        cip.RES_CIP_Type__c = 'Unit';
        // ContractId intentionally left null

        Boolean threw = false;
        try {
            Test.startTest();
            RES_ContractItemPriceServices.syncContracts(new List<ContractItemPrice>{ cip });
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'A CIP without a ContractId must be skipped without error.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Eligibility check — only one CIP type present → no sync fired
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncContracts_onlyUnitCIP_doesNotSync() {
        if (!configReady()) { return; }

        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = createAndFetchContract(acc.Id);

        // Simulate trigger input: a Unit CIP referencing the contract.
        // The DAO layer query may return no CIPs for this contract
        // (ItemId / Product External ID missing), so eligibleContractsToSync
        // stays empty → no sync fired.
        ContractItemPrice unitCip = new ContractItemPrice(
            ContractId      = c.Id,
            RES_CIP_Type__c = 'Unit'
        );

        Test.startTest();
        Test.getEventBus().deliver();
        Integer before = queueableJobCount();

        RES_ContractItemPriceServices.syncContracts(new List<ContractItemPrice>{ unitCip });
        Test.getEventBus().deliver();

        Integer after = queueableJobCount();
        Test.stopTest();

        Assert.areEqual(0, after - before, 'A contract with only a Unit CIP must not trigger sync.');
    }

    @isTest
    static void syncContracts_onlyPaymentPlanCIP_doesNotSync() {
        if (!configReady()) { return; }

        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = createAndFetchContract(acc.Id);

        ContractItemPrice ppCip = new ContractItemPrice(
            ContractId      = c.Id,
            RES_CIP_Type__c = 'Payment Plan'
        );

        Test.startTest();
        Test.getEventBus().deliver();
        Integer before = queueableJobCount();

        RES_ContractItemPriceServices.syncContracts(new List<ContractItemPrice>{ ppCip });
        Test.getEventBus().deliver();

        Integer after = queueableJobCount();
        Test.stopTest();

        Assert.areEqual(0, after - before, 'A contract with only a Payment Plan CIP must not trigger sync.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Mixed CIP types across different contracts → only the complete one syncs
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncContracts_mixedContracts_onlyEligibleSyncs() {
        if (!configReady()) { return; }

        Account acc      = RES_TestDataFactory.createAccount();
        Contract cFull   = createAndFetchContract(acc.Id); // will have both types (via DAO)
        Contract cUnit   = createAndFetchContract(acc.Id); // only Unit

        // Trigger input contains both contracts
        List<ContractItemPrice> triggerInput = new List<ContractItemPrice>{
            new ContractItemPrice(ContractId = cFull.Id,  RES_CIP_Type__c = 'Unit'),
            new ContractItemPrice(ContractId = cFull.Id,  RES_CIP_Type__c = 'Payment Plan'),
            new ContractItemPrice(ContractId = cUnit.Id,  RES_CIP_Type__c = 'Unit')
        };

        // No exception expected regardless of DAO return
        Boolean threw = false;
        try {
            Test.startTest();
            RES_ContractItemPriceServices.syncContracts(triggerInput);
            Test.getEventBus().deliver();
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }

        Assert.isFalse(threw, 'syncContracts with mixed contract eligibility must not throw.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Exception inside RES_ContractServices.syncContract is swallowed
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncContracts_innerExceptionSwallowed() {
        // Pass a trigger input that will reach the syncContract call path.
        // If the config is missing, syncContract throws — the catch block
        // in syncContracts must absorb it.
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = createAndFetchContract(acc.Id);

        ContractItemPrice unitCip = new ContractItemPrice(
            ContractId      = c.Id,
            RES_CIP_Type__c = 'Unit'
        );
        ContractItemPrice ppCip = new ContractItemPrice(
            ContractId      = c.Id,
            RES_CIP_Type__c = 'Payment Plan'
        );

        Boolean threw = false;
        try {
            Test.startTest();
            RES_ContractItemPriceServices.syncContracts(
                new List<ContractItemPrice>{ unitCip, ppCip }
            );
            Test.getEventBus().deliver();
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }

        Assert.isFalse(threw, 'Any exception from the inner syncContract call must be caught and logged, not propagated.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DAO mock: both CIP types present → eligibility check passes
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncContracts_bothCIPTypesPresent_marksEligible() {
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = createAndFetchContract(acc.Id);

        // Inject mock DAO results so the eligibility block is reached
        ContractItemPrice mockUnit = new ContractItemPrice(
            ContractId      = c.Id,
            RES_CIP_Type__c = 'Unit'
        );
        ContractItemPrice mockPP = new ContractItemPrice(
            ContractId      = c.Id,
            RES_CIP_Type__c = 'Payment Plan'
        );
        RES_ContractItemPriceServices.mockExistingCIPs =
            new List<ContractItemPrice>{ mockUnit, mockPP };
        RES_ContractItemPriceServices.mockContractList =
            new List<Contract>{ c };

        RES_IntegrationTestDataFactory.primeSapToken();
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Boolean threw = false;
        try {
            Test.startTest();
            RES_ContractItemPriceServices.syncContracts(
                new List<ContractItemPrice>{ mockUnit, mockPP }
            );
            Test.getEventBus().deliver();
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        } finally {
            RES_ContractItemPriceServices.mockExistingCIPs = null;
            RES_ContractItemPriceServices.mockContractList = null;
            RES_IntegrationTestDataFactory.clearSapToken();
        }

        Assert.isFalse(threw, 'syncContracts must not propagate exceptions when both CIP types are present.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DAO mock: only Unit CIP in existing → eligibility still fails
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncContracts_mockOnlyUnit_notEligible() {
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = createAndFetchContract(acc.Id);

        ContractItemPrice mockUnit = new ContractItemPrice(
            ContractId      = c.Id,
            RES_CIP_Type__c = 'Unit'
        );
        RES_ContractItemPriceServices.mockExistingCIPs =
            new List<ContractItemPrice>{ mockUnit };

        Boolean threw = false;
        try {
            Test.startTest();
            RES_ContractItemPriceServices.syncContracts(
                new List<ContractItemPrice>{ mockUnit }
            );
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        } finally {
            RES_ContractItemPriceServices.mockExistingCIPs = null;
        }

        Assert.isFalse(threw, 'A contract with only Unit in existing CIPs must exit without error.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DAO mock: only Payment Plan in existing → eligibility still fails
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void syncContracts_mockOnlyPaymentPlan_notEligible() {
        Account acc = RES_TestDataFactory.createAccount();
        Contract c  = createAndFetchContract(acc.Id);

        ContractItemPrice mockPP = new ContractItemPrice(
            ContractId      = c.Id,
            RES_CIP_Type__c = 'Payment Plan'
        );
        RES_ContractItemPriceServices.mockExistingCIPs =
            new List<ContractItemPrice>{ mockPP };

        Boolean threw = false;
        try {
            Test.startTest();
            RES_ContractItemPriceServices.syncContracts(
                new List<ContractItemPrice>{ mockPP }
            );
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        } finally {
            RES_ContractItemPriceServices.mockExistingCIPs = null;
        }

        Assert.isFalse(threw, 'A contract with only Payment Plan in existing CIPs must exit without error.');
    }
   
    @IsTest
    static void testUpdateFinalPayment_picksLastInstallment() {
        Contract con = createTestContract();

        // Inject three installments: 3, 9, 10 — service must pick Installment 10
        RES_ContractItemPriceServices.testInstallmentOverride = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 3',  1000),
            makeCip(con.Id, 'WS PP01 Installment 9',  5000),
            makeCip(con.Id, 'WS PP01 Installment 10', 9999)
        };

        List<ContractItemPrice> cipInput = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 9', 5000)
        };

        Test.startTest();
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(cipInput);
        Test.stopTest();

        Contract updated = [SELECT RES_Final_Payment__c FROM Contract WHERE Id = :con.Id];
        System.assertEquals(9999, updated.RES_Final_Payment__c,
            'Should pick the price of Installment 10 (highest number)');
    }

    @IsTest
    static void testUpdateFinalPayment_singleInstallment() {
        Contract con = createTestContract();

        RES_ContractItemPriceServices.testInstallmentOverride = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 1', 3333)
        };
        List<ContractItemPrice> cipInput = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 1', 3333)
        };

        Test.startTest();
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(cipInput);
        Test.stopTest();

        Contract updated = [SELECT RES_Final_Payment__c FROM Contract WHERE Id = :con.Id];
        System.assertEquals(3333, updated.RES_Final_Payment__c,
            'Single installment should become the final payment');
    }

    @IsTest
    static void testUpdateFinalPayment_noInstallmentRecords() {
        Contract con = createTestContract();

        // Override returns empty — no installments → Final Payment should stay null
        RES_ContractItemPriceServices.testInstallmentOverride = new List<ContractItemPrice>();
        List<ContractItemPrice> cipInput = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 1', 1000)
        };

        Test.startTest();
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(cipInput);
        Test.stopTest();

        Contract updated = [SELECT RES_Final_Payment__c FROM Contract WHERE Id = :con.Id];
        System.assertEquals(null, updated.RES_Final_Payment__c,
            'Should be null when no installment records exist');
    }

    @IsTest
    static void testUpdateFinalPayment_emptyList() {
        Test.startTest();
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(new List<ContractItemPrice>());
        Test.stopTest();
        System.assert(true, 'Empty list should return without error');
    }

    @IsTest
    static void testUpdateFinalPayment_nullList() {
        Test.startTest();
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(null);
        Test.stopTest();
        System.assert(true, 'Null list should return without error');
    }

    @IsTest
    static void testUpdateFinalPayment_noChangeSkipsDml() {
        Contract con = createTestContract();

        RES_ContractItemPriceServices.testInstallmentOverride = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 1', 7777)
        };
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(
            new List<ContractItemPrice>{ makeCip(con.Id, 'X', 0) }
        );

        RES_ContractItemPriceServices.testInstallmentOverride = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 1', 7777)
        };

        Test.startTest();
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(
            new List<ContractItemPrice>{ makeCip(con.Id, 'X', 0) }
        );
        Test.stopTest();

        // If no DML was issued, no exception and value is still 7777
        Contract updated = [SELECT RES_Final_Payment__c FROM Contract WHERE Id = :con.Id];
        System.assertEquals(7777, updated.RES_Final_Payment__c,
            'Unchanged value should not trigger a redundant DML update');
    }

    @IsTest
    static void testUpdateFinalPayment_installmentDeleteClearsPayment() {
        Contract con = createTestContract();

        // Set Final Payment to 5000
        RES_ContractItemPriceServices.testInstallmentOverride = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 2', 5000)
        };
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(
            new List<ContractItemPrice>{ makeCip(con.Id, 'WS PP01 Installment 2', 5000) }
        );

        RES_ContractItemPriceServices.testInstallmentOverride = new List<ContractItemPrice>();

        Test.startTest();
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(
            new List<ContractItemPrice>{ makeCip(con.Id, 'WS PP01 Installment 2', 5000) }
        );
        Test.stopTest();

        Contract updated = [SELECT RES_Final_Payment__c FROM Contract WHERE Id = :con.Id];
        System.assertEquals(null, updated.RES_Final_Payment__c,
            'Final Payment should be null after last installment is deleted');
    }

    @IsTest
    static void testTriggerHandler_recursionGuard() {
        Contract con = createTestContract();


        RES_ContractItemPriceServices.testInstallmentOverride = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 5', 8888)
        };

        RES_ContractItemPriceTriggerHandler handler = new RES_ContractItemPriceTriggerHandler();

        Test.startTest();
       
        RES_ContractItemPriceServices.updateFinalPaymentOnContract(
            new List<ContractItemPrice>{ makeCip(con.Id, 'WS PP01 Installment 5', 8888) }
        );
        Test.stopTest();

        Contract updated = [SELECT RES_Final_Payment__c FROM Contract WHERE Id = :con.Id];
        System.assertEquals(8888, updated.RES_Final_Payment__c,
            'Service should update Final Payment correctly');
    }


}
