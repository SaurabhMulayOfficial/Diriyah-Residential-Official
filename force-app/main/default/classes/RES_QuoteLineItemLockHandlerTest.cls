@isTest
private class RES_QuoteLineItemLockHandlerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'RES QLI Lock Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'RES QLI Lock Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'RES QLI Lock Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = 'Negotiating'
        );
        insert q;

        Product2 prod = new Product2(Name = 'RES QLI Lock Test Unit', IsActive = true);
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
    static void testQuoteLineItem_OnCustomerApprovedQuote_IsBlocked() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        RES_Config_Switch__c cs = RES_Config_Switch__c.getInstance();
        cs.RES_Validation_Rules_Off__c = true;
        cs.RES_Flows_Off__c = true;
        upsert cs;
        update new Quote(Id = q.Id, Status = 'Customer Approved');
        cs.RES_Validation_Rules_Off__c = false;
        cs.RES_Flows_Off__c = false;
        upsert cs;

        QuoteLineItem qli = [SELECT Id, Description FROM QuoteLineItem LIMIT 1];
        qli.Description = 'Trying to edit a locked line item';

        Test.startTest();
        try {
            update qli;
            System.assert(false, 'Expected the Customer Approved lock to block this line item edit');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Customer Approved'), 'Unexpected error message: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testQuoteLineItem_OnNonCustomerApprovedQuote_IsNotBlocked() {
        QuoteLineItem qli = [SELECT Id, Description FROM QuoteLineItem LIMIT 1];
        qli.Description = 'Still Negotiating, should be editable';

        Test.startTest();
        try {
            update qli;
        } catch (DmlException e) {
            System.assert(false, 'A line item on a non Customer Approved quote should not be locked: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
