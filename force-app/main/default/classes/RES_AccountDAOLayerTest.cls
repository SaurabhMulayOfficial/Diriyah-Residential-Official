@isTest
private class RES_AccountDAOLayerTest {

    @isTest
    static void getAccountsWithPersonContactByIds_personAccount_returnsPersonContact() {
        Id personRt = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1].Id;
        Account person = new Account(FirstName = 'Test', LastName = 'Person', PersonEmail = 'test.person@example.com', RecordTypeId = personRt);
        insert person;
        Account business = RES_TestDataFactory.createAccount();

        Map<Id, Account> result = new RES_AccountDAOLayer().getAccountsWithPersonContactByIds(new Set<Id>{ person.Id, business.Id });

        Assert.areEqual(2, result.size());
        Assert.isTrue(result.get(person.Id).IsPersonAccount);
        Assert.isNotNull(result.get(person.Id).PersonContactId, 'Person Account should expose its PersonContactId.');
        Assert.isFalse(result.get(business.Id).IsPersonAccount);
    }

    @isTest
    static void getAccountsWithPersonContactByIds_emptyInput_returnsEmptyMap() {
        Assert.isTrue(new RES_AccountDAOLayer().getAccountsWithPersonContactByIds(new Set<Id>()).isEmpty());
        Assert.isTrue(new RES_AccountDAOLayer().getAccountsWithPersonContactByIds(null).isEmpty());
    }

    @isTest
    static void otherQueries_returnTheAccount() {
        Account acc = RES_TestDataFactory.createAccount();
        Set<Id> ids = new Set<Id>{ acc.Id };
        RES_AccountDAOLayer dao = new RES_AccountDAOLayer();

        Assert.isTrue(dao.getAccountsByIds(ids).containsKey(acc.Id));
        Assert.isTrue(dao.getAccountTypesByIds(ids).containsKey(acc.Id));
        Assert.isTrue(dao.getAccountsForSyncByIds(ids).containsKey(acc.Id));
        Assert.isNotNull(dao.getAccountById(acc.Id));
        Assert.isNotNull(dao.getPersonAccountsNationalityByIds(ids));
    }
}
