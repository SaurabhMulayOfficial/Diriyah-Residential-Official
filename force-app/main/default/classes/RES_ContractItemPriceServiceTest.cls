/**
 * @description Unit tests for RES_ContractItemPriceService and
 *              RES_ContractItemPriceTriggerHandler.
 */
@IsTest
private class RES_ContractItemPriceServiceTest {

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

   
    @IsTest
    static void testUpdateFinalPayment_picksLastInstallment() {
        Contract con = createTestContract();

        // Inject three installments: 3, 9, 10 — service must pick Installment 10
        RES_ContractItemPriceService.testInstallmentOverride = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 3',  1000),
            makeCip(con.Id, 'WS PP01 Installment 9',  5000),
            makeCip(con.Id, 'WS PP01 Installment 10', 9999)
        };

        List<ContractItemPrice> cipInput = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 9', 5000)
        };

        Test.startTest();
        RES_ContractItemPriceService.updateFinalPaymentOnContract(cipInput);
        Test.stopTest();

        Contract updated = [SELECT RES_Final_Payment__c FROM Contract WHERE Id = :con.Id];
        System.assertEquals(9999, updated.RES_Final_Payment__c,
            'Should pick the price of Installment 10 (highest number)');
    }

    @IsTest
    static void testUpdateFinalPayment_singleInstallment() {
        Contract con = createTestContract();

        RES_ContractItemPriceService.testInstallmentOverride = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 1', 3333)
        };
        List<ContractItemPrice> cipInput = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 1', 3333)
        };

        Test.startTest();
        RES_ContractItemPriceService.updateFinalPaymentOnContract(cipInput);
        Test.stopTest();

        Contract updated = [SELECT RES_Final_Payment__c FROM Contract WHERE Id = :con.Id];
        System.assertEquals(3333, updated.RES_Final_Payment__c,
            'Single installment should become the final payment');
    }

    @IsTest
    static void testUpdateFinalPayment_noInstallmentRecords() {
        Contract con = createTestContract();

        // Override returns empty — no installments → Final Payment should stay null
        RES_ContractItemPriceService.testInstallmentOverride = new List<ContractItemPrice>();
        List<ContractItemPrice> cipInput = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 1', 1000)
        };

        Test.startTest();
        RES_ContractItemPriceService.updateFinalPaymentOnContract(cipInput);
        Test.stopTest();

        Contract updated = [SELECT RES_Final_Payment__c FROM Contract WHERE Id = :con.Id];
        System.assertEquals(null, updated.RES_Final_Payment__c,
            'Should be null when no installment records exist');
    }

    @IsTest
    static void testUpdateFinalPayment_emptyList() {
        Test.startTest();
        RES_ContractItemPriceService.updateFinalPaymentOnContract(new List<ContractItemPrice>());
        Test.stopTest();
        System.assert(true, 'Empty list should return without error');
    }

    @IsTest
    static void testUpdateFinalPayment_nullList() {
        Test.startTest();
        RES_ContractItemPriceService.updateFinalPaymentOnContract(null);
        Test.stopTest();
        System.assert(true, 'Null list should return without error');
    }

    @IsTest
    static void testUpdateFinalPayment_noChangeSkipsDml() {
        Contract con = createTestContract();

        RES_ContractItemPriceService.testInstallmentOverride = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 1', 7777)
        };
        RES_ContractItemPriceService.updateFinalPaymentOnContract(
            new List<ContractItemPrice>{ makeCip(con.Id, 'X', 0) }
        );

        RES_ContractItemPriceService.testInstallmentOverride = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 1', 7777)
        };

        Test.startTest();
        RES_ContractItemPriceService.updateFinalPaymentOnContract(
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
        RES_ContractItemPriceService.testInstallmentOverride = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 2', 5000)
        };
        RES_ContractItemPriceService.updateFinalPaymentOnContract(
            new List<ContractItemPrice>{ makeCip(con.Id, 'WS PP01 Installment 2', 5000) }
        );

        RES_ContractItemPriceService.testInstallmentOverride = new List<ContractItemPrice>();

        Test.startTest();
        RES_ContractItemPriceService.updateFinalPaymentOnContract(
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


        RES_ContractItemPriceService.testInstallmentOverride = new List<ContractItemPrice>{
            makeCip(con.Id, 'WS PP01 Installment 5', 8888)
        };

        RES_ContractItemPriceTriggerHandler handler = new RES_ContractItemPriceTriggerHandler();

        Test.startTest();
       
        RES_ContractItemPriceService.updateFinalPaymentOnContract(
            new List<ContractItemPrice>{ makeCip(con.Id, 'WS PP01 Installment 5', 8888) }
        );
        Test.stopTest();

        Contract updated = [SELECT RES_Final_Payment__c FROM Contract WHERE Id = :con.Id];
        System.assertEquals(8888, updated.RES_Final_Payment__c,
            'Service should update Final Payment correctly');
    }
}
