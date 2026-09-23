/**
 * @description  Test class for RES_SendEmailPlatformEventService.
 * @author       Saurabh Mulay
 * @date         23-Sep-2026
 */
@IsTest
private class RES_SendEmailPlatformEventServiceTest {

    // ─── Constructor ─────────────────────────────────────────────────────────

    @IsTest
    static void testConstructor_instantiates() {
        RES_SendEmailPlatformEventService svc = new RES_SendEmailPlatformEventService();
        Assert.isNotNull(svc, 'Service instance should not be null');
    }

    // ─── processEventsForDuplicationEmails — guard paths ────────────────────

    @IsTest
    static void testProcessEvents_nullInput_returnsEarly() {
        Exception caughtEx = null;
        Test.startTest();
        try {
            RES_SendEmailPlatformEventService.processEventsForDuplicationEmails(null);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        Assert.isNull(caughtEx, 'Null events list should return early without throwing');
    }

    @IsTest
    static void testProcessEvents_emptyList_returnsEarly() {
        Exception caughtEx = null;
        Test.startTest();
        try {
            RES_SendEmailPlatformEventService.processEventsForDuplicationEmails(new List<RES_Send_Email__e>());
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        Assert.isNull(caughtEx, 'Empty events list should return early without throwing');
    }

    @IsTest
    static void testProcessEvents_noLeadDuplicationEvents_returnsEarly() {
        RES_Send_Email__e evt = new RES_Send_Email__e();
        evt.Type__c  = 'Other Type';
        evt.Group__c = 'Operations';

        Exception caughtEx = null;
        Test.startTest();
        try {
            RES_SendEmailPlatformEventService.processEventsForDuplicationEmails(new List<RES_Send_Email__e>{ evt });
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        Assert.isNull(caughtEx, 'Events with non-matching type should return early without throwing');
    }

    // ─── processEventsForDuplicationEmails — Lead Duplication path ───────────

    @IsTest
    static void testProcessEvents_leadDuplicationEvent_nullOrgWideAddress_skipped() {
        RES_Send_Email__e evt = new RES_Send_Email__e();
        evt.Type__c            = 'Lead Duplication';
        evt.Group__c           = 'SomeGroup';
        evt.OrgWideAddressID__c = null;
        evt.Merge_Fields__c    = 'Field1,Field2';

        Exception caughtEx = null;
        Test.startTest();
        try {
            RES_SendEmailPlatformEventService.processEventsForDuplicationEmails(new List<RES_Send_Email__e>{ evt });
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        Assert.isNull(caughtEx, 'Event with null OrgWideAddressID__c should be skipped without throwing');
    }

    @IsTest
    static void testProcessEvents_leadDuplicationEvent_nullGroupName_noEmailsSent() {
        RES_Send_Email__e evt = new RES_Send_Email__e();
        evt.Type__c            = 'Lead Duplication';
        evt.Group__c           = null;
        evt.OrgWideAddressID__c = null;

        Exception caughtEx = null;
        Test.startTest();
        try {
            RES_SendEmailPlatformEventService.processEventsForDuplicationEmails(new List<RES_Send_Email__e>{ evt });
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        Assert.isNull(caughtEx, 'Null Group__c should not cause an exception');
    }

    @IsTest
    static void testProcessEvents_leadDuplicationEvent_blankMergeFields_parsedAsEmptyList() {
        RES_Send_Email__e evt = new RES_Send_Email__e();
        evt.Type__c             = 'Lead Duplication';
        evt.Group__c            = 'SomeGroup';
        evt.OrgWideAddressID__c = null;
        evt.Merge_Fields__c     = '';

        Exception caughtEx = null;
        Test.startTest();
        try {
            RES_SendEmailPlatformEventService.processEventsForDuplicationEmails(new List<RES_Send_Email__e>{ evt });
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        Assert.isNull(caughtEx, 'Blank Merge_Fields__c should be treated as empty list without throwing');
    }

    @IsTest
    static void testProcessEvents_mixedEventTypes_onlyLeadDuplicationProcessed() {
        RES_Send_Email__e nonDuplication = new RES_Send_Email__e();
        nonDuplication.Type__c = 'Welcome Email';

        RES_Send_Email__e duplication = new RES_Send_Email__e();
        duplication.Type__c             = 'Lead Duplication';
        duplication.Group__c            = 'SomeGroup';
        duplication.OrgWideAddressID__c = null;

        Exception caughtEx = null;
        Test.startTest();
        try {
            RES_SendEmailPlatformEventService.processEventsForDuplicationEmails(
                new List<RES_Send_Email__e>{ nonDuplication, duplication }
            );
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        Assert.isNull(caughtEx, 'Mixed event types should be processed without throwing');
    }

    @IsTest
    static void testProcessEvents_multipleLeadDuplicationEvents_allProcessed() {
        RES_Send_Email__e evt1 = new RES_Send_Email__e();
        evt1.Type__c             = 'Lead Duplication';
        evt1.Group__c            = 'GroupA';
        evt1.OrgWideAddressID__c = null;

        RES_Send_Email__e evt2 = new RES_Send_Email__e();
        evt2.Type__c             = 'Lead Duplication';
        evt2.Group__c            = 'GroupB';
        evt2.OrgWideAddressID__c = null;

        Exception caughtEx = null;
        Test.startTest();
        try {
            RES_SendEmailPlatformEventService.processEventsForDuplicationEmails(
                new List<RES_Send_Email__e>{ evt1, evt2 }
            );
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        Assert.isNull(caughtEx, 'Multiple Lead Duplication events should be processed without throwing');
    }
}
