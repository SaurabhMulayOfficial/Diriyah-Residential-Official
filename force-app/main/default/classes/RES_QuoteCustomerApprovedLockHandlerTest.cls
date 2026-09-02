@isTest
private class RES_QuoteCustomerApprovedLockHandlerTest {

    private static Id residentialRecordTypeId() {
        return Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName().get('RES_Residential_Sales').getRecordTypeId();
    }

    private static void moveToCustomerApproved(Id quoteId) {
        // The org already has an unrelated legacy rule requiring the Quote be synced first;
        // bypass validation rules just for this transition (our new lock checks RES_Triggers_Off__c, not this).
        RES_Config_Switch__c cs = RES_Config_Switch__c.getInstance();
        cs.RES_Validation_Rules_Off__c = true;
        cs.RES_Flows_Off__c = true;
        upsert cs;
        update new Quote(Id = quoteId, Status = 'Customer Approved');
        cs.RES_Validation_Rules_Off__c = false;
        cs.RES_Flows_Off__c = false;
        upsert cs;
    }

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'RES Lock Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'RES Lock Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'RES Lock Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            RecordTypeId = residentialRecordTypeId(),
            Status = 'Negotiating'
        );
        insert q;
    }

    @isTest
    static void testCustomerApprovedQuote_UnrelatedFieldEdit_IsBlocked() {
        Quote q = [SELECT Id, Status FROM Quote LIMIT 1];
        moveToCustomerApproved(q.Id);

        Quote toEdit = [SELECT Id, Description FROM Quote WHERE Id = :q.Id];
        toEdit.Description = 'Trying to sneak an edit in';

        Test.startTest();
        try {
            update toEdit;
            System.assert(false, 'Expected the Customer Approved lock to block this edit');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Customer Approved and is locked'), 'Unexpected error message: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testCustomerApprovedQuote_AllowListedFields_AreNotBlocked() {
        Quote q = [SELECT Id, Status FROM Quote LIMIT 1];
        moveToCustomerApproved(q.Id);

        Map<String, Object> fieldsToTry = new Map<String, Object>{
            'RES_Extend_Soft_Hold_By_Hours__c' => 5,
            'RES_Unit_Blocked_End_Date__c' => Date.today().addDays(1),
            'RES_Unit_Blocked_Start_Date__c' => Date.today(),
            'RES_Approval_Request_Remarks__c' => 'remark',
            'RES_Product_Soft_Held__c' => false
        };

        Test.startTest();
        for (String fieldName : fieldsToTry.keySet()) {
            Quote toEdit = new Quote(Id = q.Id);
            toEdit.put(fieldName, fieldsToTry.get(fieldName));
            try {
                update toEdit;
            } catch (DmlException e) {
                System.assert(false, fieldName + ' should not be blocked: ' + e.getMessage());
            }
        }
        Test.stopTest();
    }

    @isTest
    static void testCustomerApprovedQuote_CancelTransition_IsAllowed() {
        Quote q = [SELECT Id, Status FROM Quote LIMIT 1];
        moveToCustomerApproved(q.Id);

        Quote toCancel = [SELECT Id, Status FROM Quote WHERE Id = :q.Id];
        toCancel.Status = 'Cancelled';
        toCancel.RES_Cancellation_Reason__c = 'Test cancellation reason';

        Test.startTest();
        try {
            update toCancel;
        } catch (DmlException e) {
            System.assert(false, 'Cancelling should not be blocked: ' + e.getMessage());
        }
        Test.stopTest();

        Quote reloaded = [SELECT Status FROM Quote WHERE Id = :q.Id];
        System.assertEquals('Cancelled', reloaded.Status);
    }

    @isTest
    static void testCustomerApprovedQuote_TriggersOffSwitch_BypassesLock() {
        RES_Config_Switch__c cs = RES_Config_Switch__c.getInstance();
        cs.RES_Triggers_Off__c = true;
        upsert cs;

        Quote q = [SELECT Id, Status FROM Quote LIMIT 1];
        moveToCustomerApproved(q.Id);

        Quote toEdit = [SELECT Id, Description FROM Quote WHERE Id = :q.Id];
        toEdit.Description = 'Should go through because triggers are switched off';

        Test.startTest();
        try {
            update toEdit;
        } catch (DmlException e) {
            System.assert(false, 'Triggers Off switch should bypass the lock entirely: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testNonCustomerApprovedQuote_IsNotLocked() {
        Quote q = [SELECT Id, Status, Description FROM Quote LIMIT 1];
        q.Description = 'Still Negotiating, should be editable';

        Test.startTest();
        try {
            update q;
        } catch (DmlException e) {
            System.assert(false, 'A non Customer Approved quote should not be locked: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
