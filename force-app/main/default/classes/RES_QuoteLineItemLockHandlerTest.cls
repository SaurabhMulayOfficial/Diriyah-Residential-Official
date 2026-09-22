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

    // DIR-1777: the old lock blocked ANY update to a Customer Approved line item unconditionally
    // (it never checked which field changed), which also blocked the pricing engine's own
    // recalculation writes and left quotes permanently stuck at CalculationStatus =
    // SaveFailedOrIncomplete. A resave with no genuine (user-editable) field change must now be
    // allowed through - this is what a platform-only field write (e.g. NetUnitPrice, which no
    // DML, including this test's, can set directly since it isn't updateable) looks like from the
    // trigger's point of view.
    @isTest
    static void testQuoteLineItem_ResaveWithNoFieldChange_OnCustomerApprovedQuote_IsNotBlocked() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        RES_Config_Switch__c cs = RES_Config_Switch__c.getInstance();
        cs.RES_Validation_Rules_Off__c = true;
        cs.RES_Flows_Off__c = true;
        upsert cs;
        update new Quote(Id = q.Id, Status = 'Customer Approved');
        cs.RES_Validation_Rules_Off__c = false;
        cs.RES_Flows_Off__c = false;
        upsert cs;

        QuoteLineItem qli = [SELECT Id FROM QuoteLineItem LIMIT 1];

        Test.startTest();
        try {
            update qli;
        } catch (DmlException e) {
            System.assert(false, 'A resave with no genuine field change should not be blocked, since that is what the pricing engine\'s own recalculation writes look like: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // Confirms Quantity specifically - the field most likely to be mistaken for a "pricing" field
    // and accidentally exempted - is still genuinely user-editable and stays locked.
    @isTest
    static void testQuoteLineItem_QuantityChange_OnCustomerApprovedQuote_IsBlocked() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        RES_Config_Switch__c cs = RES_Config_Switch__c.getInstance();
        cs.RES_Validation_Rules_Off__c = true;
        cs.RES_Flows_Off__c = true;
        upsert cs;
        update new Quote(Id = q.Id, Status = 'Customer Approved');
        cs.RES_Validation_Rules_Off__c = false;
        cs.RES_Flows_Off__c = false;
        upsert cs;

        QuoteLineItem qli = [SELECT Id, Quantity FROM QuoteLineItem LIMIT 1];
        qli.Quantity = qli.Quantity + 1;

        Test.startTest();
        try {
            update qli;
            System.assert(false, 'Expected the Customer Approved lock to block a Quantity edit');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Customer Approved'), 'Unexpected error message: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // DIR-1777: confirmed live against an actual stuck swap quote that the pricing engine needs to
    // write UnitPrice on the -1 quantity "outgoing product" line itself (it was left at
    // UnitPrice = null alongside a stale ListPrice/TotalPrice). This must be exempt only on quotes
    // that genuinely have a negative-quantity line (a swap) - see
    // testQuoteLineItem_UnitPriceChange_OnNonSwapQuote_IsStillBlocked for the regression guard.
    @isTest
    static void testQuoteLineItem_UnitPriceChange_OnNegativeQtyLine_IsNotBlocked() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        RES_Config_Switch__c cs = RES_Config_Switch__c.getInstance();
        cs.RES_Validation_Rules_Off__c = true;
        cs.RES_Flows_Off__c = true;
        upsert cs;
        update new Quote(Id = q.Id, Status = 'Customer Approved');
        cs.RES_Validation_Rules_Off__c = false;
        cs.RES_Flows_Off__c = false;
        upsert cs;

        cs.RES_Triggers_Off__c = true;
        upsert cs;
        QuoteLineItem negLine = [SELECT Id FROM QuoteLineItem LIMIT 1];
        negLine.Quantity = -1;
        update negLine;
        cs.RES_Triggers_Off__c = false;
        upsert cs;

        QuoteLineItem toEdit = new QuoteLineItem(Id = negLine.Id, UnitPrice = 55);

        Test.startTest();
        try {
            update toEdit;
        } catch (DmlException e) {
            System.assert(false, 'UnitPrice on a negative-quantity swap line should not be blocked: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // DIR-1777: confirmed live that the recalculation ALSO needs to write UnitPrice on the swap
    // pair's +1 "incoming product" line (it was left at UnitPrice = 0 while its own
    // NetUnitPrice/TotalPrice already showed the true, non-zero price). The exemption is scoped to
    // the whole quote (any negative-quantity sibling makes it a swap), not just the negative line
    // itself, so this positive-quantity line must be exempt too as long as it has a
    // negative-quantity sibling.
    @isTest
    static void testQuoteLineItem_UnitPriceChange_OnPositiveLineOfSwapQuote_IsNotBlocked() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        QuoteLineItem positiveLine = [SELECT Id, QuoteId, PricebookEntryId FROM QuoteLineItem LIMIT 1];

        RES_Config_Switch__c cs = RES_Config_Switch__c.getInstance();
        cs.RES_Triggers_Off__c = true;
        upsert cs;
        QuoteLineItem negativeLine = new QuoteLineItem(
            QuoteId = positiveLine.QuoteId,
            PricebookEntryId = positiveLine.PricebookEntryId,
            Quantity = -1,
            UnitPrice = 100
        );
        insert negativeLine;
        cs.RES_Triggers_Off__c = false;
        upsert cs;

        cs.RES_Validation_Rules_Off__c = true;
        cs.RES_Flows_Off__c = true;
        upsert cs;
        update new Quote(Id = q.Id, Status = 'Customer Approved');
        cs.RES_Validation_Rules_Off__c = false;
        cs.RES_Flows_Off__c = false;
        upsert cs;

        QuoteLineItem toEdit = new QuoteLineItem(Id = positiveLine.Id, UnitPrice = 61426502);

        Test.startTest();
        try {
            update toEdit;
        } catch (DmlException e) {
            System.assert(false, 'UnitPrice on the positive-quantity line of a swap quote should not be blocked: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // Regression guard: on a quote that is NOT a swap (no negative-quantity line at all), a
    // normal line's UnitPrice - the price an approver actually signed off on - must stay locked,
    // so the swap carve-out above can't be used to tamper with pricing on an ordinary approved quote.
    @isTest
    static void testQuoteLineItem_UnitPriceChange_OnNonSwapQuote_IsStillBlocked() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        RES_Config_Switch__c cs = RES_Config_Switch__c.getInstance();
        cs.RES_Validation_Rules_Off__c = true;
        cs.RES_Flows_Off__c = true;
        upsert cs;
        update new Quote(Id = q.Id, Status = 'Customer Approved');
        cs.RES_Validation_Rules_Off__c = false;
        cs.RES_Flows_Off__c = false;
        upsert cs;

        QuoteLineItem qli = [SELECT Id, UnitPrice FROM QuoteLineItem LIMIT 1];
        qli.UnitPrice = (qli.UnitPrice == null ? 0 : qli.UnitPrice) + 1;

        Test.startTest();
        try {
            update qli;
            System.assert(false, 'Expected the Customer Approved lock to block a UnitPrice edit on a non-swap quote');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Customer Approved'), 'Unexpected error message: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // DIR-1777: confirmed live against an actual stuck swap quote that the pricing engine's
    // recalculation writes ValidationResult and ConstraintEngineNodeStatus__c on the line item
    // itself (not just Quote.ValidationResult) - both must be exempt or the lock still blocks
    // repricing. ConstraintEngineNodeStatus__c only exists in orgs with Revenue Cloud's
    // constraint engine provisioned, so this skips it where the org's schema doesn't have it
    // rather than failing SObject.put() with "Invalid field" - EXEMPT_FIELDS itself is safe
    // either way, since RES_QuoteLineItemLockHandler only ever compares against fields that
    // actually appear in Schema.SObjectType.QuoteLineItem.fields.getMap().
    @isTest
    static void testQuoteLineItem_ExemptEngineStatusFields_OnCustomerApprovedQuote_AreNotBlocked() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        RES_Config_Switch__c cs = RES_Config_Switch__c.getInstance();
        cs.RES_Validation_Rules_Off__c = true;
        cs.RES_Flows_Off__c = true;
        upsert cs;
        update new Quote(Id = q.Id, Status = 'Customer Approved');
        cs.RES_Validation_Rules_Off__c = false;
        cs.RES_Flows_Off__c = false;
        upsert cs;

        Map<String, Object> fieldsToTry = new Map<String, Object>{
            'ValidationResult' => 'Warning',
            'ConstraintEngineNodeStatus__c' => '{"cfgStatus":"Default","attributes":[]}'
        };
        Map<String, Schema.SObjectField> qliFields = Schema.SObjectType.QuoteLineItem.fields.getMap();

        Test.startTest();
        for (String fieldName : fieldsToTry.keySet()) {
            if (!qliFields.containsKey(fieldName.toLowerCase())) {
                continue; // not provisioned in this org - nothing to exercise
            }
            QuoteLineItem toEdit = new QuoteLineItem(Id = [SELECT Id FROM QuoteLineItem LIMIT 1].Id);
            toEdit.put(fieldName, fieldsToTry.get(fieldName));
            try {
                update toEdit;
            } catch (DmlException e) {
                System.assert(false, fieldName + ' should not be blocked: ' + e.getMessage());
            }
        }
        Test.stopTest();
    }
}
