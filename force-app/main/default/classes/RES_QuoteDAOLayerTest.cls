@isTest
private class RES_QuoteDAOLayerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'RES QuoteDAO Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'RES QuoteDAO Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Contract con = new Contract(AccountId = acc.Id, Status = 'Draft', StartDate = Date.today());
        insert con;

        Quote q = new Quote(
            Name = 'RES QuoteDAO Test Quote',
            OpportunityId = opp.Id,
            ContractId = con.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = 'Customer Approved'
        );
        insert q;
    }

    @isTest
    static void testGetQuotesByOpportunityIds_ReturnsMatchingQuotes() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<Quote> results = new RES_QuoteDAOLayer().getQuotesByOpportunityIds(new Set<Id>{ opp.Id });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should find the one quote on this opportunity');
    }

    @isTest
    static void testGetQuotesByOpportunityIds_EmptySet_ReturnsEmptyList() {
        Test.startTest();
        List<Quote> results = new RES_QuoteDAOLayer().getQuotesByOpportunityIds(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Empty input should short-circuit to an empty list');
    }

    @isTest
    static void testGetQuotesByContractIds_NotSyncing_ReturnsNoMatch() {
        // IsSyncing can't be set via plain DML (it's only settable through the native Quote/Opportunity
        // sync mechanism), so a freshly inserted test Quote is never syncing - this still exercises the
        // query path and confirms the IsSyncing filter is applied.
        Contract con = [SELECT Id FROM Contract LIMIT 1];

        Test.startTest();
        List<Quote> results = new RES_QuoteDAOLayer().getQuotesByContractIds(new Set<Id>{ con.Id }, 'Customer Approved');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Non-syncing quote should not match the IsSyncing = true filter');
    }

    @isTest
    static void testGetQuotesByContractIds_EmptySet_ReturnsEmptyList() {
        Test.startTest();
        List<Quote> results = new RES_QuoteDAOLayer().getQuotesByContractIds(new Set<Id>(), 'Customer Approved');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Empty input should short-circuit to an empty list');
    }

    @isTest
    static void testGetQuotesByIds_ReturnsMapKeyedById() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        Map<Id, Quote> results = new RES_QuoteDAOLayer().getQuotesByIds(new Set<Id>{ q.Id });
        Test.stopTest();

        System.assert(results.containsKey(q.Id), 'Result map should be keyed by Quote Id');
        System.assertEquals('Customer Approved', results.get(q.Id).Status);
    }

    @isTest
    static void testGetQuotesByIds_EmptySet_ReturnsEmptyMap() {
        Test.startTest();
        Map<Id, Quote> results = new RES_QuoteDAOLayer().getQuotesByIds(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Empty input should short-circuit to an empty map');
    }
}
