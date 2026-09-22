@isTest
private class RES_QuoteLineItemProductHandlerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'RES QLI Product Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'RES QLI Product Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'RES QLI Product Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = 'Negotiating'
        );
        insert q;

        Id residentialUnitRTId = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName()
            .get('RES_Residential_Sales')?.getRecordTypeId();

        Product2 unit = new Product2(Name = 'RES QLI Product Test Unit', IsActive = true, RecordTypeId = residentialUnitRTId);
        insert unit;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = unit.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;
    }

    @isTest
    static void testInsertQuoteLineItem_PopulatesQuoteProduct() {
        Quote q = [SELECT Id, RES_Product__c FROM Quote LIMIT 1];
        PricebookEntry pbe = [SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.Name = 'RES QLI Product Test Unit' LIMIT 1];

        Test.startTest();
        insert new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 100);
        Test.stopTest();

        Quote updated = [SELECT RES_Product__c FROM Quote WHERE Id = :q.Id];
        System.assertEquals(pbe.Product2Id, updated.RES_Product__c, 'Quote Product should be populated from the inserted line item');
    }

    @isTest
    static void testDeleteOnlyQuoteLineItem_ClearsQuoteProduct() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        PricebookEntry pbe = [SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.Name = 'RES QLI Product Test Unit' LIMIT 1];
        QuoteLineItem qli = new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 100);
        insert qli;

        Test.startTest();
        delete qli;
        Test.stopTest();

        Quote updated = [SELECT RES_Product__c FROM Quote WHERE Id = :q.Id];
        System.assertEquals(null, updated.RES_Product__c, 'Quote Product should be cleared once its line item is deleted');
    }
}
