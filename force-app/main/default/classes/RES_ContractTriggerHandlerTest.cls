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
    static void afterInsert_contractInsert_doesNotThrow() {
        Account acc = RES_TestDataFactory.createAccount();
        Boolean threw = false;
        try {
            Test.startTest();
            Contract c = new Contract(
                AccountId = acc.Id,
                Status    = 'Draft',
                StartDate = Date.today()
            );
            insert c;
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'Contract insert must not throw from the trigger handler.');
    }

    @isTest
    static void afterUpdate_contractUpdate_doesNotThrow() {
        Account acc = RES_TestDataFactory.createAccount();
        Contract c = new Contract(
            AccountId = acc.Id,
            Status    = 'Draft',
            StartDate = Date.today()
        );
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
}
