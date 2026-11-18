/**
 * Class Name: RES_ContractCreationDateHijriTest
 * Description: Covers RES_Contract_AfterSave_Populate_CreationDate_Hijri (Hijri creation date stamped on Contract insert).
 */
@IsTest
private class RES_ContractCreationDateHijriTest {
    @IsTest
    static void insert_stampsHijriCreationDate() {
        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        // Person Account used on purpose: a business Account insert enqueues the SAP sync, which fails in tests
        List<RecordType> rts = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1];
        if (rts.isEmpty()) {
            return; // Person Accounts not available in this org
        }
        Account acc = new Account(LastName = 'Test', PersonEmail = 'test.hijri@example.com', PersonMobilePhone = '+966500000003', RecordTypeId = rts[0].Id);
        insert acc;
        Contract con = new Contract(AccountId = acc.Id, Status = 'Draft', StartDate = Date.today());
        Test.startTest();
        insert con;
        Test.stopTest();

        Contract saved = [SELECT CreatedDate, RES_Document_CreationDate_Hijri__c FROM Contract WHERE Id = :con.Id];
        RES_HijriDateUtility.HijriDate h = RES_HijriDateUtility.convert(saved.CreatedDate.dateGmt());
        String expected = String.valueOf(h.day).leftPad(2, '0') + '/' + String.valueOf(h.month).leftPad(2, '0') + '/' + h.year;
        System.assertEquals(expected, saved.RES_Document_CreationDate_Hijri__c, 'Hijri creation date should match the GMT creation day');
    }
}
