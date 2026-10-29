@isTest
private class RES_ContractTriggerHandlerTest {

    @isTest
    static void handler_constructor_instantiatesWithoutError() {
        Boolean threw = false;
        try {
            RES_ContractTriggerHandler handler = new RES_ContractTriggerHandler();
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'Handler constructor must not throw.');
    }

    @isTest
    static void handleAfterInsert_doesNotThrow() {
        Boolean threw = false;
        try {
            Test.startTest();
            RES_ContractTriggerHandler.handleAfterInsert(new List<Contract>());
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'handleAfterInsert must not throw.');
    }

    @isTest
    static void handleAfterUpdate_doesNotThrow() {
        Boolean threw = false;
        try {
            Test.startTest();
            RES_ContractTriggerHandler.handleAfterUpdate(
                new List<Contract>(),
                new Map<Id, Contract>()
            );
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'handleAfterUpdate must not throw.');
    }

    @isTest
    static void afterInsert_contractInsert_firesTrigger() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = RES_TestDataFactory.createAccount();
        Boolean threw = false;
        try {
            Test.startTest();
            insert new Contract(AccountId = acc.Id, Status = 'Draft', StartDate = Date.today());
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'Contract insert must not throw from the trigger handler.');
    }

    @isTest
    static void afterUpdate_contractUpdate_firesTrigger() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = RES_TestDataFactory.createAccount();
        Contract c = new Contract(AccountId = acc.Id, Status = 'Draft', StartDate = Date.today());
        insert c;

        Boolean threw = false;
        try {
            Test.startTest();
            c.Description = 'Updated';
            update c;
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'Contract update must not throw from the trigger handler.');
    }

    @isTest
    static void setFeeTransferred_lastAmountBlankToValue_setsTrue() {
        Id cId = fakeContractId();
        Contract oldC = new Contract(Id = cId, RES_Last_Amount_Received__c = null, RES_Fee_Transferred__c = false);
        Contract newC = new Contract(Id = cId, RES_Last_Amount_Received__c = 5000, RES_Fee_Transferred__c = false);
        RES_ContractTriggerHandler.handleBeforeUpdate(new List<Contract>{ newC }, new Map<Id, Contract>{ cId => oldC });
        Assert.isTrue(newC.RES_Fee_Transferred__c, 'Fee Transferred should be set when Last Amount Received is first populated.');
    }

    @isTest
    static void setFeeTransferred_lastAmountAlreadySet_unchanged() {
        Id cId = fakeContractId();
        Contract oldC = new Contract(Id = cId, RES_Last_Amount_Received__c = 1000, RES_Fee_Transferred__c = false);
        Contract newC = new Contract(Id = cId, RES_Last_Amount_Received__c = 5000, RES_Fee_Transferred__c = false);
        RES_ContractTriggerHandler.handleBeforeUpdate(new List<Contract>{ newC }, new Map<Id, Contract>{ cId => oldC });
        Assert.isFalse(newC.RES_Fee_Transferred__c, 'Fee Transferred should not change when Last Amount Received was already populated.');
    }

    @isTest
    static void trackAmounts_firstPayment_setsReservationAndTotal() {
        Id cId = fakeContractId();
        Contract oldC = contractWith(cId, null, null, 10000);
        Contract newC = contractWith(cId, 1000, null, 10000);
        RES_ContractTriggerHandler.trackAmountsReceived(new List<Contract>{ newC }, new Map<Id, Contract>{ cId => oldC });
        Assert.areEqual(1000, newC.RES_Reservation_Amount_Received__c, 'First payment should be the reservation amount.');
        Assert.areEqual(1000, newC.RES_Total_Amount_Received__c, 'Total should start at the first payment.');
        Assert.isNull(newC.RES_Final_Payment_Received__c, 'Final payment should stay blank until the contract value is reached.');
    }

    @isTest
    static void trackAmounts_laterPayment_addsToTotalKeepsReservation() {
        Id cId = fakeContractId();
        Contract oldC = contractWith(cId, 1000, 1000, 10000);
        Contract newC = contractWith(cId, 4000, 1000, 10000);
        newC.RES_Reservation_Amount_Received__c = 1000;
        RES_ContractTriggerHandler.trackAmountsReceived(new List<Contract>{ newC }, new Map<Id, Contract>{ cId => oldC });
        Assert.areEqual(1000, newC.RES_Reservation_Amount_Received__c, 'Reservation amount must not change after the first payment.');
        Assert.areEqual(5000, newC.RES_Total_Amount_Received__c, 'Total should add the new payment.');
        Assert.isNull(newC.RES_Final_Payment_Received__c, 'Final payment should stay blank below the contract value.');
    }

    @isTest
    static void trackAmounts_totalReachesContractValue_setsFinalPayment() {
        Id cId = fakeContractId();
        Contract oldC = contractWith(cId, 4000, 6000, 10000);
        Contract newC = contractWith(cId, 4000, 6000, 10000);
        newC.RES_Last_Amount_Received_Date__c = Date.today();
        RES_ContractTriggerHandler.trackAmountsReceived(new List<Contract>{ newC }, new Map<Id, Contract>{ cId => oldC });
        Assert.areEqual(10000, newC.RES_Total_Amount_Received__c, 'Same amount on a new date counts as a new payment.');
        Assert.areEqual(4000, newC.RES_Final_Payment_Received__c, 'Payment reaching the contract value is the final payment.');
    }

    @isTest
    static void trackAmounts_unchangedPayment_noChange() {
        Id cId = fakeContractId();
        Contract oldC = contractWith(cId, 2000, 3000, 10000);
        Contract newC = contractWith(cId, 2000, 3000, 10000);
        RES_ContractTriggerHandler.trackAmountsReceived(new List<Contract>{ newC }, new Map<Id, Contract>{ cId => oldC });
        Assert.areEqual(3000, newC.RES_Total_Amount_Received__c, 'Unrelated updates must not add to the total.');
    }

    @isTest
    static void trackAmounts_contractUpdate_populatesFields() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Account acc = RES_TestDataFactory.createAccount();
        Contract c = new Contract(AccountId = acc.Id, Status = 'Draft', StartDate = Date.today());
        insert c;

        Test.startTest();
        update new Contract(Id = c.Id, RES_Last_Amount_Received__c = 1500, RES_Last_Amount_Received_Date__c = Date.today());
        update new Contract(Id = c.Id, RES_Last_Amount_Received__c = 2500, RES_Last_Amount_Received_Date__c = Date.today().addDays(1));
        Test.stopTest();

        Contract saved = [SELECT RES_Reservation_Amount_Received__c, RES_Total_Amount_Received__c, RES_Final_Payment_Received__c
                          FROM Contract WHERE Id = :c.Id];
        Assert.areEqual(1500, saved.RES_Reservation_Amount_Received__c, 'Reservation should be the first payment.');
        Assert.areEqual(4000, saved.RES_Total_Amount_Received__c, 'Total should sum both payments.');
        Assert.isNull(saved.RES_Final_Payment_Received__c, 'No contract value, so no final payment.');
    }

    @isTest
    static void populateCustomerSignedBy_businessAccount_usesFirstContact() {
        Account acc = RES_TestDataFactory.createAccount();
        Contact first = new Contact(LastName = 'First', AccountId = acc.Id);
        insert first;
        insert new Contact(LastName = 'Second', AccountId = acc.Id);

        Contract c = new Contract(AccountId = acc.Id);
        RES_ContractServices.populateCustomerSignedBy(new List<Contract>{ c });
        Assert.areEqual(first.Id, c.CustomerSignedId, 'Business Account should use its first-created Contact.');
    }

    @isTest
    static void populateCustomerSignedBy_personAccount_usesPersonContact() {
        Id personRt = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1].Id;
        Account person = new Account(FirstName = 'Test', LastName = 'Person', PersonEmail = 'test.person@example.com', RecordTypeId = personRt);
        insert person;
        Id personContactId = [SELECT PersonContactId FROM Account WHERE Id = :person.Id].PersonContactId;

        Contract c = new Contract(AccountId = person.Id);
        RES_ContractServices.populateCustomerSignedBy(new List<Contract>{ c });
        Assert.areEqual(personContactId, c.CustomerSignedId, 'Person Account should use its own Contact.');
    }

    @isTest
    static void populateCustomerSignedBy_alreadySet_overwritten() {
        Account acc = RES_TestDataFactory.createAccount();
        Contact accountContact = new Contact(LastName = 'AccountContact', AccountId = acc.Id);
        Contact stray = new Contact(LastName = 'Stray', AccountId = acc.Id);
        insert new List<Contact>{ accountContact, stray };

        Contract c = new Contract(AccountId = acc.Id, CustomerSignedId = stray.Id);
        RES_ContractServices.populateCustomerSignedBy(new List<Contract>{ c });
        Assert.areEqual(accountContact.Id, c.CustomerSignedId, 'Create always overwrites with the Account contact.');
    }

    // Total Contract Value is a roll-up, so it can only be set via deserialization
    private static Contract contractWith(Id cId, Decimal lastAmount, Decimal total, Decimal contractValue) {
        return (Contract) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Contract' },
            'Id' => cId,
            'RES_Last_Amount_Received__c' => lastAmount,
            'RES_Total_Amount_Received__c' => total,
            'RES_Total_Contract_Value__c' => contractValue
        }), Contract.class);
    }

    private static Id fakeContractId() {
        return Contract.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
    }
}
