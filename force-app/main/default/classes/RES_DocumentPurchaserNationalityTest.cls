/**
 * Class Name: RES_DocumentPurchaserNationalityTest
 * Description: Unit tests for RES_DocumentPurchaserNationality. Verifies the picklist
 *              label is resolved for Account (Person Account) and Contact, that blank
 *              values clear the Document Nationality, and that the Contract path works.
 */
@IsTest
private class RES_DocumentPurchaserNationalityTest {
    private static String firstValue(Schema.DescribeFieldResult f) {
        for (Schema.PicklistEntry e : f.getPicklistValues()) {
            if (e.isActive()) {
                return e.getValue();
            }
        }
        return null;
    }

    @IsTest
    static void contact_populatesLabel() {
        String value = firstValue(Contact.RES_Nationality__c.getDescribe());
        String expected = RES_NationalityServices.getPicklistValuesMap(Contact.RES_Nationality__c.getDescribe()).get(value);
        Contact c = new Contact(LastName = 'Test', RES_Nationality__c = value);
        insert c;

        RES_DocumentPurchaserNationality.Input input = new RES_DocumentPurchaserNationality.Input();
        input.contactRecord = [SELECT Id, RES_Nationality__c, RES_Document_Nationality__c FROM Contact WHERE Id = :c.Id];
        Test.startTest();
        RES_DocumentPurchaserNationality.validateOpportunity(new List<RES_DocumentPurchaserNationality.Input>{ input });
        Test.stopTest();

        System.assertEquals(expected.left(255), [SELECT RES_Document_Nationality__c FROM Contact WHERE Id = :c.Id].RES_Document_Nationality__c, 'Label should be stamped');
    }

    @IsTest
    static void contact_blankClearsDocumentNationality() {
        Contact c = new Contact(LastName = 'Test', RES_Document_Nationality__c = 'Old');
        insert c;

        RES_DocumentPurchaserNationality.Input input = new RES_DocumentPurchaserNationality.Input();
        input.contactRecord = [SELECT Id, RES_Nationality__c, RES_Document_Nationality__c FROM Contact WHERE Id = :c.Id];
        Test.startTest();
        RES_DocumentPurchaserNationality.validateOpportunity(new List<RES_DocumentPurchaserNationality.Input>{ input });
        Test.stopTest();

        System.assertEquals(null, [SELECT RES_Document_Nationality__c FROM Contact WHERE Id = :c.Id].RES_Document_Nationality__c, 'Should be cleared');
    }

    @IsTest
    static void personAccount_populatesLabel() {
        List<RecordType> rts = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1];
        if (rts.isEmpty()) {
            return; // Person Accounts not available in this org
        }
        String value = firstValue(Account.RES_Nationality__pc.getDescribe());
        String expected = RES_NationalityServices.getPicklistValuesMap(Account.RES_Nationality__pc.getDescribe()).get(value);
        Account a = new Account(LastName = 'Test', PersonEmail = 'test.nationality@example.com', PersonMobilePhone = '+966500000000', RecordTypeId = rts[0].Id, RES_Nationality__pc = value);
        insert a;

        RES_DocumentPurchaserNationality.Input input = new RES_DocumentPurchaserNationality.Input();
        input.accountRecord = [SELECT Id, RES_Nationality__pc, RES_Document_Nationality__pc FROM Account WHERE Id = :a.Id];
        Test.startTest();
        RES_DocumentPurchaserNationality.validateOpportunity(new List<RES_DocumentPurchaserNationality.Input>{ input });
        Test.stopTest();

        System.assertEquals(expected.left(255), [SELECT RES_Document_Nationality__pc FROM Account WHERE Id = :a.Id].RES_Document_Nationality__pc, 'Label should be stamped');
    }

    @IsTest
    static void contract_populatesLabel() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        String value = firstValue(Contract.RES_PAR_Nationality__c.getDescribe());
        String expected = RES_NationalityServices.getPicklistValuesMap(Contract.RES_PAR_Nationality__c.getDescribe()).get(value);
        // Person Account used on purpose: a business Account insert enqueues the SAP sync, which fails in tests
        List<RecordType> rts = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1];
        if (rts.isEmpty()) {
            return; // Person Accounts not available in this org
        }
        Account acc = new Account(LastName = 'Test', PersonEmail = 'test.contract@example.com', PersonMobilePhone = '+966500000001', RecordTypeId = rts[0].Id);
        insert acc;
        Contract con = new Contract(AccountId = acc.Id, Status = 'Draft', StartDate = Date.today(), RES_PAR_Nationality__c = value);
        Test.startTest();
        insert con;
        Test.stopTest();

        RES_DocumentPurchaserNationality.Input input = new RES_DocumentPurchaserNationality.Input();
        input.contractRecord = [SELECT Id, RES_PAR_Nationality__c FROM Contract WHERE Id = :con.Id];
        RES_DocumentPurchaserNationality.validateOpportunity(new List<RES_DocumentPurchaserNationality.Input>{ input });

        System.assertEquals(expected, [SELECT RES_Document_PAR_Nationality__c FROM Contract WHERE Id = :con.Id].RES_Document_PAR_Nationality__c, 'Contract label should be stamped');
    }

    @IsTest
    static void contractNationalityMap_isNotEmpty() {
        System.assertNotEquals(0, RES_NationalityServices.getPicklistValuesMap(Contract.RES_PAR_Nationality__c.getDescribe()).size(), 'Contract nationality map should have entries');
    }
}
