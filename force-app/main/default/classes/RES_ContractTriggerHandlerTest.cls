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
    static void afterInsert_testVisible_doesNotThrow() {
        RES_ContractTriggerHandler handler = new RES_ContractTriggerHandler();
        Boolean threw = false;
        try {
            Test.startTest();
            handler.afterInsert();
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'afterInsert must not throw.');
    }

    @isTest
    static void afterUpdate_testVisible_doesNotThrow() {
        RES_ContractTriggerHandler handler = new RES_ContractTriggerHandler();
        Boolean threw = false;
        try {
            Test.startTest();
            handler.afterUpdate();
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }
        Assert.isFalse(threw, 'afterUpdate must not throw.');
    }
}
