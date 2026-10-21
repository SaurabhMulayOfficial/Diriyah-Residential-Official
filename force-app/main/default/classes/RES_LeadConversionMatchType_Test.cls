/**
 * Test Class    : RES_LeadConversionMatchType_Test
 * Description   : Verifies that Lead conversion only reuses an existing Account / Contact of the
 *                 same type as the Lead (Company Lead -> Business Account, Individual Lead -> Person Account).
 *                 Cross-type mobile / email matches must not fail the conversion - new records are created.
 */
@isTest
private class RES_LeadConversionMatchType_Test {

    private static final String PROJECT = 'Amansamar Residences Wadi Safar';

    private static Account createPersonAccount(String mobile, String email) {
        Account pa = new Account(
            RecordTypeId      = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            FirstName         = 'Person',
            LastName          = 'Existing',
            PersonMobilePhone = mobile,
            PersonEmail       = email
        );
        insert pa;
        return pa;
    }

    private static Account createBusinessAccountWithContact(String mobile, String email) {
        Account acc = RES_TestDataFactory.createCompanyRTAccount('Existing Business', '8624' + String.valueOf(Math.abs(Crypto.getRandomInteger())).left(6));
        RES_TestDataFactory.createContact(acc.Id, email, mobile);
        return acc;
    }

    private static Lead createLead(Boolean isIndividual, String email, String mobile) {
        Lead l = new Lead(
            OwnerId           = UserInfo.getUserId(),
            RecordTypeId      = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
                                    .get(isIndividual ? 'RES_Individual' : 'RES_Company').getRecordTypeId(),
            FirstName         = 'Lead',
            LastName          = 'Tester',
            Company           = isIndividual ? null : 'Match Type Co',
            Status            = '04',
            Email             = email,
            MobilePhone       = mobile,
            RES_Project__c    = PROJECT,
            RES_SLA_Status__c = 'Met'
        );
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.duplicateRuleHeader.allowSave = true;
        Database.SaveResult sr = Database.insert(l, dml);
        System.assert(sr.isSuccess(), 'Lead insert failed: ' + sr.getErrors());
        return l;
    }

    private static Lead convert(Lead l) {
        Test.startTest();
        RES_LeadConversionHandler.handleLeadConversion(new List<Lead>{ l });
        Test.stopTest();
        return [SELECT Id, IsConverted, ConvertedAccountId, ConvertedContactId, ConvertedOpportunityId,
                       ConvertedAccount.IsPersonAccount
                FROM Lead WHERE Id = :l.Id];
    }

    // ── Cross-type: must create NEW records ───────────────────────────────

    @IsTest
    static void companyLeadMobileMatchesPersonAccount_createsNewBusinessAccount() {
        Account pa = createPersonAccount('+966500011111', 'pa1@test.com');
        Lead result = convert(createLead(false, 'co1@test.com', '+966500011111'));

        System.assertEquals(true, result.IsConverted, 'Lead should convert');
        System.assertNotEquals(pa.Id, result.ConvertedAccountId, 'Person Account must not be reused');
        System.assertEquals(false, result.ConvertedAccount.IsPersonAccount, 'A Business Account should be created');
        System.assertNotEquals(null, result.ConvertedContactId);
        System.assertNotEquals(null, result.ConvertedOpportunityId);
    }

    @IsTest
    static void individualLeadMobileMatchesBusinessContact_createsNewPersonAccount() {
        Account biz = createBusinessAccountWithContact('+966500022222', 'biz2@test.com');
        Lead result = convert(createLead(true, 'ind2@test.com', '+966500022222'));

        System.assertEquals(true, result.IsConverted, 'Lead should convert');
        System.assertNotEquals(biz.Id, result.ConvertedAccountId, 'Business Account must not be reused');
        System.assertEquals(true, result.ConvertedAccount.IsPersonAccount, 'A Person Account should be created');
        System.assertNotEquals(null, result.ConvertedOpportunityId);
    }

    @IsTest
    static void companyLeadEmailMatchesPersonAccountEmail_createsNewBusinessAccount() {
        Account pa = createPersonAccount('+966500033331', 'shared3@test.com');
        Lead result = convert(createLead(false, 'shared3@test.com', '+966500033332'));

        System.assertEquals(true, result.IsConverted, 'Lead should convert');
        System.assertNotEquals(pa.Id, result.ConvertedAccountId);
        System.assertEquals(false, result.ConvertedAccount.IsPersonAccount);
    }

    @IsTest
    static void individualLeadEmailMatchesBusinessContactEmail_createsNewPersonAccount() {
        Account biz = createBusinessAccountWithContact('+966500044441', 'shared4@test.com');
        Lead result = convert(createLead(true, 'shared4@test.com', '+966500044442'));

        System.assertEquals(true, result.IsConverted, 'Lead should convert');
        System.assertNotEquals(biz.Id, result.ConvertedAccountId);
        System.assertEquals(true, result.ConvertedAccount.IsPersonAccount);
    }

    // ── Same type: existing behaviour must be kept (match is honoured) ────

    @IsTest
    static void individualLeadMobileMatchesPersonAccount_reusesPersonAccount() {
        Account pa = createPersonAccount('+966500055555', 'pa5@test.com');
        Lead result = convert(createLead(true, 'ind5@test.com', '+966500055555'));

        System.assertEquals(true, result.IsConverted, 'Lead should convert');
        System.assertEquals(pa.Id, result.ConvertedAccountId, 'Existing Person Account should be reused');
    }

    @IsTest
    static void individualLeadEmailMatchesPersonAccount_reusesPersonAccount() {
        Account pa = createPersonAccount('+966500066661', 'shared6@test.com');
        Lead result = convert(createLead(true, 'shared6@test.com', '+966500066662'));

        System.assertEquals(true, result.IsConverted, 'Lead should convert');
        System.assertEquals(pa.Id, result.ConvertedAccountId, 'Existing Person Account should be reused');
    }

    @IsTest
    static void companyLeadMobileMatchesBusinessContact_reusesBusinessAccountAndContact() {
        Account biz = createBusinessAccountWithContact('+966500077777', 'biz7@test.com');
        Contact existing = [SELECT Id FROM Contact WHERE AccountId = :biz.Id LIMIT 1];
        Lead result = convert(createLead(false, 'co7@test.com', '+966500077777'));

        System.assertEquals(true, result.IsConverted, 'Lead should convert');
        System.assertEquals(biz.Id, result.ConvertedAccountId, 'Existing Business Account should be reused');
        System.assertEquals(existing.Id, result.ConvertedContactId, 'Existing Business Contact should be reused');
    }

    // ── Same mobile used by both a Person Account and a Business contact ──

    @IsTest
    static void companyLeadMobileSharedByBothTypes_picksBusinessContact() {
        createPersonAccount('+966500088888', 'pa8@test.com');
        Account biz = createBusinessAccountWithContact('+966500088888', 'biz8@test.com');
        Contact bizContact = [SELECT Id FROM Contact WHERE AccountId = :biz.Id LIMIT 1];
        Lead result = convert(createLead(false, 'co8@test.com', '+966500088888'));

        System.assertEquals(true, result.IsConverted, 'Lead should convert');
        System.assertEquals(biz.Id, result.ConvertedAccountId);
        System.assertEquals(bizContact.Id, result.ConvertedContactId);
    }

    @IsTest
    static void individualLeadMobileSharedByBothTypes_picksPersonAccount() {
        Account pa = createPersonAccount('+966500099999', 'pa9@test.com');
        createBusinessAccountWithContact('+966500099999', 'biz9@test.com');
        Lead result = convert(createLead(true, 'ind9@test.com', '+966500099999'));

        System.assertEquals(true, result.IsConverted, 'Lead should convert');
        System.assertEquals(pa.Id, result.ConvertedAccountId);
    }

    // ── Resolver unit checks ──────────────────────────────────────────────

    @IsTest
    static void resolver_unknownRecordType_keepsPreviousBehaviour() {
        Account biz = createBusinessAccountWithContact('+966500010101', 'biz10@test.com');
        Contact con = [SELECT Id FROM Contact WHERE AccountId = :biz.Id LIMIT 1];
        Lead l = new Lead(MobilePhone = '+966500010101');
        l.Id = '00Q000000000001AAA';

        Map<Id, RES_LeadConversionHandler.ConversionTarget> targets = RES_LeadConversionHandler.resolveConversionTargets(
            new List<Lead>{ l },
            new Map<Id,List<SObject>>{ l.Id => new List<SObject>{ biz } },
            new Map<String,Id>{ '+966500010101' => con.Id }
        );
        System.assertEquals(biz.Id, targets.get(l.Id).accountId);
        System.assertEquals(con.Id, targets.get(l.Id).contactId);
    }
}
