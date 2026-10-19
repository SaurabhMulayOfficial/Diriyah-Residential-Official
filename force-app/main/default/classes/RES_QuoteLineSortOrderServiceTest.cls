@isTest
private class RES_QuoteLineSortOrderServiceTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'RES QLI Sort Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'RES QLI Sort Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        insert new Quote(
            Name = 'RES QLI Sort Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = 'Negotiating'
        );

        Id installmentRTId = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName()
            .get('RES_Residential_Installment')?.getRecordTypeId();
        List<Product2> products = new List<Product2>{
            new Product2(Name = 'RES Sort Installment 2', IsActive = true, RES_Sequence__c = 2, RecordTypeId = installmentRTId),
            new Product2(Name = 'RES Sort Installment 1', IsActive = true, RES_Sequence__c = 1, RecordTypeId = installmentRTId),
            new Product2(Name = 'RES Sort Unit', IsActive = true)
        };
        insert products;

        List<PricebookEntry> entries = new List<PricebookEntry>();
        for (Product2 product : products) {
            entries.add(new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = product.Id, UnitPrice = 100, IsActive = true));
        }
        insert entries;
    }

    @isTest
    static void testInsert_SetsSortOrderFromSequence() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        List<QuoteLineItem> lines = new List<QuoteLineItem>();
        for (PricebookEntry pbe : [SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.Name LIKE 'RES Sort%']) {
            lines.add(new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = pbe.Product2Id, Quantity = 1, UnitPrice = 100));
        }

        Test.startTest();
        insert lines;
        Test.stopTest();

        Map<String, Integer> sortByName = new Map<String, Integer>();
        for (QuoteLineItem line : [SELECT Product2.Name, SortOrder FROM QuoteLineItem WHERE QuoteId = :q.Id]) {
            sortByName.put(line.Product2.Name, line.SortOrder);
        }
        System.assertEquals(1, sortByName.get('RES Sort Installment 1'), 'Installment 1 should sort first');
        System.assertEquals(2, sortByName.get('RES Sort Installment 2'), 'Installment 2 should sort second');
        System.assertEquals(null, sortByName.get('RES Sort Unit'), 'Lines without a sequence keep the default order');
    }
}
