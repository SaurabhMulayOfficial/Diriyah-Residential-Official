/**
 * ==============================================================================
 * Test Class    : RES_LeadMassConversionUtility_Test
 * Description   : Unit tests for RES_LeadMassConversionUtility.
 *                 Test data creation is fully delegated to
 *                 RES_TestDataFactory — this class
 *                 only contains test assertions and execution logic.
 *
 * Coverage      : isInvalidRequest() · collectLeadIds() · fetchConvertedStatus()
 *                 fetchLeads() · validateLeadOwners() · handleResults()
 *
 * Author        : Rohan Jambhule
 * Company       : Globant Inc
 * Created Date  : May 9, 2025
 * Version       : 9.0
 * ==============================================================================
 */
@isTest
private class RES_LeadMassConversionUtility_Test {

    // ─────────────────────────────────────────────────────────────────
    // @testSetup : Users created once and reused across all tests.
    // Isolating user DML (setup object) here prevents MIXED_DML errors
    // when Lead DML (non-setup object) runs inside individual tests.
    // ─────────────────────────────────────────────────────────────────
    @testSetup
    static void setupUsers() {
        RES_TestDataFactory.createSalesRepUser();
        RES_TestDataFactory.createSalesDirectorUser();
        RES_TestDataFactory.createSalesManagerUser();
    }

    // ─────────────────────────────────────────────────────────────────
    // User fetchers — thin wrappers to keep test bodies readable
    // ─────────────────────────────────────────────────────────────────
    private static User getSalesRep() {
        return [SELECT Id FROM User WHERE Email = 'res.salesrep.test@example.com'      LIMIT 1];
    }
    private static User getSalesDirector() {
        return [SELECT Id FROM User WHERE Email = 'res.salesdirector.test@example.com' LIMIT 1];
    }
    private static User getSalesManager() {
        return [SELECT Id FROM User WHERE Email = 'res.salesmanager.test@example.com'  LIMIT 1];
    }

    // ══════════════════════════════════════════════════════════════════
    // TEST 1 : Empty request list → graceful return
    // Covers : isInvalidRequest() — empty list branch
    // Runs as : Sales Relationship Manager
    // ══════════════════════════════════════════════════════════════════
    @isTest
    static void testEmptyRequestListShouldReturnGracefully() {
        System.runAs(getSalesRep()) {
            Lead l = RES_TestDataFactory.createLead('empty.request@example.com');

            Test.startTest();
            RES_LeadMassConversionUtility.convertLeads(
                new List<RES_LeadMassConversionUtility.ConvertRequest>()
            );
            Test.stopTest();
            System.assertEquals(false,
                [SELECT IsConverted FROM Lead WHERE Id = :l.Id].IsConverted,
                'Lead must NOT be converted when an empty request list is passed.');
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // TEST 2 : Null request list → graceful return
    // Covers : isInvalidRequest() — null branch
    // Runs as : Sales Relationship Manager
    // ══════════════════════════════════════════════════════════════════
    @isTest
    static void testNullRequestListShouldReturnGracefully() {
        System.runAs(getSalesRep()) {
            Lead l = RES_TestDataFactory.createLead('null.request@example.com');
            Test.startTest();
            RES_LeadMassConversionUtility.convertLeads(null);
            Test.stopTest();
            System.assertEquals(false,
                [SELECT IsConverted FROM Lead WHERE Id = :l.Id].IsConverted,
                'Lead must NOT be converted when a null request list is passed.');
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // TEST 3 : Request with null leads → leadIds empty → early return
    // Covers : collectLeadIds() null-guard + leadIds.isEmpty() RED line
    // Runs as : Sales Director
    // ══════════════════════════════════════════════════════════════════
    @isTest
    static void testRequestWithNullLeadsShouldReturnGracefully() {
        System.runAs(getSalesDirector()) {
            Lead l = RES_TestDataFactory.createLead('nullleads.request@example.com');
            RES_LeadMassConversionUtility.ConvertRequest req =
                new RES_LeadMassConversionUtility.ConvertRequest();
            req.leads                = null;
            req.convertedStatusLabel = RES_TestDataFactory.getConvertedStatus();
            req.doNotCreateOpp       = true;
            Test.startTest();
            RES_LeadMassConversionUtility.convertLeads(
                new List<RES_LeadMassConversionUtility.ConvertRequest>{ req }
            );
            Test.stopTest();
            System.assertEquals(false,
                [SELECT IsConverted FROM Lead WHERE Id = :l.Id].IsConverted,
                'Lead must NOT be converted when request has null leads list.');
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // TEST 4 : Ghost lead ID → fetchLeads returns empty → early return
    // Covers : leadsToConvert.isEmpty() return
    // Runs as : Sales Director
    // ══════════════════════════════════════════════════════════════════
    @isTest
    static void testGhostLeadIdShouldNotConvert() {
        System.runAs(getSalesDirector()) {
            Lead ghost = RES_TestDataFactory.createLead('ghost@example.com');
            Id   ghostId = ghost.Id;
            delete ghost;
            Lead control = RES_TestDataFactory.createLead('ghost.control@example.com');
            Test.startTest();
            RES_LeadMassConversionUtility.convertLeads(
                new List<RES_LeadMassConversionUtility.ConvertRequest>{
                    RES_TestDataFactory.buildRequest(
                        new List<Lead>{ new Lead(Id = ghostId) },
                        RES_TestDataFactory.getConvertedStatus(),
                        true
                    )
                }
            );
            Test.stopTest();
            System.assertEquals(false,
                [SELECT IsConverted FROM Lead WHERE Id = :control.Id].IsConverted,
                'Control lead must NOT be converted when only a ghost Id is supplied.');
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // TEST 5 : Blank status label → AuraHandledException
    // Covers : fetchConvertedStatus() → isBlank → throw RED line
    // Runs as : Sales Manager
    // ══════════════════════════════════════════════════════════════════
    @isTest
    static void testInvalidConvertedStatusShouldThrowException() {
        System.runAs(getSalesManager()) {
            Lead l = RES_TestDataFactory.createLead('invalid.status@example.com');
            Boolean exceptionThrown = false;
            Test.startTest();
            try {
                RES_LeadMassConversionUtility.convertLeads(
                    new List<RES_LeadMassConversionUtility.ConvertRequest>{
                        RES_TestDataFactory.buildRequest(
                            new List<Lead>{ l }, '', true   // blank label → DAO returns blank → throw
                        )
                    }
                );
            } catch (AuraHandledException e) {
                exceptionThrown = true;
            }
            Test.stopTest();
            System.assertEquals(true, exceptionThrown,
                'AuraHandledException must be thrown for a blank status label.');
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // TEST 6 : Queue-owned lead → AuraHandledException
    // Covers : validateLeadOwners() → add(l.Name) RED line + throw RED line
    // Runs as : Sales Manager
    // Note   : Group + QueueSObject (setup objects) inserted BEFORE
    //          System.runAs to avoid MIXED_DML_OPERATION error.
    // ══════════════════════════════════════════════════════════════════
    @isTest
    static void testQueueOwnedLeadShouldThrowException() {
        // Setup objects must be inserted outside System.runAs
        Group leadQueue = new Group(Name = 'Test Lead Queue', Type = 'Queue');
        insert leadQueue;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new QueueSObject(QueueId = leadQueue.Id, SObjectType = 'Lead');
        }
        System.runAs(getSalesManager()) {
            Lead l = RES_TestDataFactory.createLead('queue.owned@example.com');
            l.OwnerId = leadQueue.Id;
            update l;
            Boolean exceptionThrown = false;
            Test.startTest();
            try {
                RES_LeadMassConversionUtility.convertLeads(
                    new List<RES_LeadMassConversionUtility.ConvertRequest>{
                        RES_TestDataFactory.buildRequest(
                            new List<Lead>{ new Lead(Id = l.Id) },
                            RES_TestDataFactory.getConvertedStatus(),
                            true
                        )
                    }
                );
            } catch (AuraHandledException e) {
                exceptionThrown = true;
            }
            Test.stopTest();
            System.assertEquals(true, exceptionThrown,
                'AuraHandledException must be thrown when a lead is owned by a Queue.');
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // TEST 7 : handleResults null/empty guard — no exception thrown
    // Covers : handleResults() → null/empty return RED line
    // Runs as : Sales Relationship Manager
    // ══════════════════════════════════════════════════════════════════
    @isTest
    static void testHandleResultsNullEmptyGuard() {
        System.runAs(getSalesRep()) {
            Lead ghost = RES_TestDataFactory.createLead('handleresults.ghost@example.com');
            Id   ghostId = ghost.Id;
            delete ghost;
            Boolean noException = true;
            Test.startTest();
            try {
                RES_LeadMassConversionUtility.convertLeads(
                    new List<RES_LeadMassConversionUtility.ConvertRequest>{
                        RES_TestDataFactory.buildRequest(
                            new List<Lead>{ new Lead(Id = ghostId) },
                            RES_TestDataFactory.getConvertedStatus(),
                            true
                        )
                    }
                );
            } catch (Exception e) {
                noException = false;
            }
            Test.stopTest();
            System.assertEquals(true, noException,
                'No exception should be thrown when leads list is empty after fetch.');
        }
    }
    // ══════════════════════════════════════════════════════════════════
// TEST 8 : Successful single lead conversion
// Covers : executeConversion() → prepareLeadConvertOperations()
//          → handleResults() success branch
// Runs as : Sales Manager
// ══════════════════════════════════════════════════════════════════
@isTest
static void testSuccessfulLeadConversion() {
    System.runAs(getSalesManager()) {
        Lead l = RES_TestDataFactory.createLead('success.convert@example.com');
        Test.startTest();
        RES_LeadMassConversionUtility.convertLeads(
            new List<RES_LeadMassConversionUtility.ConvertRequest>{
                RES_TestDataFactory.buildRequest(
                    new List<Lead>{ l },
                    RES_TestDataFactory.getConvertedStatus(),
                    true  // doNotCreateOpp = true (simpler conversion)
                )
            }
        );
        Test.stopTest();

        System.assertEquals(true,
            [SELECT IsConverted FROM Lead WHERE Id = :l.Id].IsConverted,
            'Lead MUST be converted successfully.');
    }
}
}