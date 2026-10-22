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

    private static Id fakeContractId() {
        return Contract.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
    }
}
