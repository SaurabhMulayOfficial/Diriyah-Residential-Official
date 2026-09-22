@isTest
private class RES_QuoteLineItemDAOTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'RES QLI DAO Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'RES QLI DAO Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'RES QLI DAO Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = 'Negotiating'
        );
        insert q;

        Product2 prod = new Product2(Name = 'RES QLI DAO Test Unit', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert qli;
    }

    @isTest
    static void testGetQuoteLineItemsByOpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<QuoteLineItem> result = new RES_QuoteLineItemDAO().getQuoteLineItemsByOpportunity(new Set<Id>{opp.Id});
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Expected one QuoteLineItem for the seeded opportunity');
    }

    @isTest
    static void testGetQuoteLineItemsByProductIds() {
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];

        Test.startTest();
        List<QuoteLineItem> result = new RES_QuoteLineItemDAO().getQuoteLineItemsByProductIds(new Set<Id>{prod.Id});
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Expected one QuoteLineItem for the seeded product');
    }

    @isTest
    static void testGetQuoteLineItemsByQuoteIds() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        List<QuoteLineItem> result = new RES_QuoteLineItemDAO().getQuoteLineItemsByQuoteIds(new Set<Id>{q.Id});
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Expected one QuoteLineItem for the seeded quote');
    }

    @isTest
    static void testGetQuoteLineItemsFiltered() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];

        Test.startTest();
        List<QuoteLineItem> result = new RES_QuoteLineItemDAO().getQuoteLineItemsFiltered(
            new Set<Id>{q.Id}, new Set<Id>{prod.Id}
        );
        Test.stopTest();

        System.assertEquals(0, result.size(), 'The seeded quote is excluded, so nothing should match');
    }

    @isTest
    static void testGetAllQuoteLineItemsByOpportunityIncludingSoftHeld() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<QuoteLineItem> result = new RES_QuoteLineItemDAO().getAllQuoteLineItemsByOpportunityIncludingSoftHeld(
            new Set<Id>{opp.Id}
        );
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Expected one QuoteLineItem for the seeded opportunity');
    }

    @isTest
    static void testGetQuoteLineItemQuantitiesByQuoteIds() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        List<QuoteLineItem> result = new RES_QuoteLineItemDAO().getQuoteLineItemQuantitiesByQuoteIds(new Set<Id>{q.Id});
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Expected one QuoteLineItem for the seeded quote');
        System.assertEquals(1, result[0].Quantity);
    }

    @isTest
    static void testGetActiveQuoteLineItemsByProductIdsExcludingOpportunities() {
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];

        Test.startTest();
        List<QuoteLineItem> result = new RES_QuoteLineItemDAO().getActiveQuoteLineItemsByProductIdsExcludingOpportunities(
            new Set<Id>{prod.Id}, new Set<Id>()
        );
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Expected one QuoteLineItem for the seeded product');
    }

    @isTest
    static void testGetActiveQuoteLineItemsByProductIdsExcludingOpportunities_EmptyProductIds() {
        Test.startTest();
        List<QuoteLineItem> result = new RES_QuoteLineItemDAO().getActiveQuoteLineItemsByProductIdsExcludingOpportunities(
            new Set<Id>(), new Set<Id>()
        );
        Test.stopTest();

        System.assertEquals(0, result.size(), 'A null/empty productIds set should short-circuit to an empty list');
    }
}
