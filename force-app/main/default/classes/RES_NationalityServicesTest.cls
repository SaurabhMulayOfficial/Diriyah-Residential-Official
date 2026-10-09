/**
 * Class Name: RES_NationalityServicesTest
 * Description: Unit tests for RES_NationalityServices edge cases (blank / unknown values,
 *              empty inputs) and the nationality DAO queries. End-to-end label stamping for
 *              Contract, Person Account and Contact is covered in RES_DocumentPurchaserNationalityTest.
 */
@IsTest
private class RES_NationalityServicesTest {
    @IsTest
    static void resolveLabel_blankAndUnknownReturnNull() {
        Map<String, String> labels = new Map<String, String>{ 'SA' => 'Saudi' };
        System.assertEquals('Saudi', RES_NationalityServices.resolveLabel(labels, 'SA'), 'Known value resolves to label');
        System.assertEquals(null, RES_NationalityServices.resolveLabel(labels, null), 'Null value');
        System.assertEquals(null, RES_NationalityServices.resolveLabel(labels, ''), 'Blank value');
        System.assertEquals(null, RES_NationalityServices.resolveLabel(labels, 'XX'), 'Unknown value');
    }

    @IsTest
    static void resolveLabel_truncatesToFieldLength() {
        Map<String, String> labels = new Map<String, String>{ 'LONG' => 'A'.repeat(300) };
        System.assertEquals(255, RES_NationalityServices.resolveLabel(labels, 'LONG').length(), 'Label cut to 255');
    }

    @IsTest
    static void emptyInputs_doNothing() {
        Test.startTest();
        RES_NationalityServices.populateContractDocumentNationality(new Set<Id>());
        RES_NationalityServices.populatePersonAccountDocumentNationality(new Set<Id>());
        RES_NationalityServices.populateContactDocumentNationality(null);
        Test.stopTest();
        System.assert(new RES_ContractDAOLayer().getContractsNationalityByIds(null).isEmpty(), 'Contract DAO empty input');
        System.assert(new RES_AccountDAOLayer().getPersonAccountsNationalityByIds(null).isEmpty(), 'Account DAO empty input');
        System.assert(new RES_ContactDAOLayer().getContactsNationalityByIds(null).isEmpty(), 'Contact DAO empty input');
    }

    @IsTest
    static void invocable_nullAndEmptyInputs_doNothing() {
        RES_DocumentPurchaserNationality.validateOpportunity(null);
        RES_DocumentPurchaserNationality.validateOpportunity(new List<RES_DocumentPurchaserNationality.Input>());
        RES_DocumentPurchaserNationality.validateOpportunity(new List<RES_DocumentPurchaserNationality.Input>{ new RES_DocumentPurchaserNationality.Input() });
        System.assert(true, 'No exception thrown');
    }
}
