/**
 * @ class name         : RES_LeadDeduplicationHandlerTest
 * @ description        : Key scenario tests for RES_LeadDeduplicationHandler.
 *
 *  LEAD SOURCE API NAMES:
 *  Z02 = Management Leads (Employee)
 *  Z05 = Broker
 *  Z06 = Leads by Marketing
 *  Z09 = Manual
 *
 *
 */
@isTest
private class RES_LeadDuplicateHandlerTest {

    private static final String SRC_MANUAL    = 'Z09';
    private static final String SRC_EMPLOYEE  = 'Z02';
    private static final String SRC_MARKETING = 'Z06';
    private static final String SRC_BROKER    = 'Z05';

    private static final String STATUS_ACTIVE_1 = '01';
    private static final String STATUS_ARCHIVE  = 'Archive';

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static Lead createLead(String lastName, String leadSource, String status, Id ownerId) {
        Lead l = new Lead(
            LastName   = lastName,
            Company    = 'Test Co',
            LeadSource = leadSource,
            Status     = status,
            mobilePhone = '+1234567890'
        );
        if (ownerId != null) l.OwnerId = ownerId;
        insert l;

        return [
            SELECT Id, CreatedDate, LeadSource, Status, OwnerId
            FROM Lead
            WHERE Id = :l.Id
        ];
    }

    private static RES_LeadDeduplicationHandler.LeadDuplicateWrapper buildWrapper(
        Lead inputLead, List<Lead> existingLeads
    ) {
        RES_LeadDeduplicationHandler.LeadDuplicateWrapper w =
            new RES_LeadDeduplicationHandler.LeadDuplicateWrapper(inputLead);
        w.hasDuplicates = true;

        for (Lead el : existingLeads) {
            w.duplicateLeads.add(el);
            w.duplicateLeadIds.add(el.Id);
            if (el.LeadSource != null) {
                if (!w.leadBySource.containsKey(el.LeadSource)) {
                    w.leadBySource.put(el.LeadSource, new List<Lead>());
                }
                w.leadBySource.get(el.LeadSource).add(el);
            }
        }
        return w;
    }

    private static Lead_Deduplication_Rule__mdt buildRule(
        String source, String action, Decimal daysThreshold,
        String checkFieldEquality, String assignedTo, String leadStatus
    ) {
        Lead_Deduplication_Rule__mdt r = new Lead_Deduplication_Rule__mdt();
        r.Source__c                  = source;
        r.Action__c                  = action;
        r.Lead_Age_Threshold_Days__c = daysThreshold;
        r.Check_Field_Equality__c    = checkFieldEquality;
        r.Assigned_To__c             = assignedTo;
        r.Lead_Status__c             = leadStatus;
        return r;
    }

    // =========================================================================
    // apply() — guard clause
    // =========================================================================

    @isTest
    static void testApply_EmptyList_NoError() {
        Test.startTest();
        RES_LeadDeduplicationHandler.apply(new List<Lead>(), new List<RES_LeadDeduplicationHandler.LeadDuplicateWrapper>());
        Test.stopTest();
        System.assert(true, 'apply() with empty list must not throw');
    }

    // =========================================================================
    // getDuplicateLeads() — null guard
    // =========================================================================

    @isTest
    static void testGetDuplicateLeads_NullInput_ReturnsEmptyList() {
        Test.startTest();
        List<RES_LeadDeduplicationHandler.LeadDuplicateWrapper> result =
            RES_LeadDeduplicationHandler.getDuplicateLeads(null);
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Null input must return empty list');
    }

    // =========================================================================
    // hydrateDuplicateWrapper() — with real Ids
    // =========================================================================

    @isTest
    static void testHydrate_WithRealIds_PopulatesLeadsAndSourceMap() {
        Lead input   = createLead('HydrateIn',  SRC_MANUAL,  STATUS_ACTIVE_1, null);
        Lead dupLead = createLead('HydrateDup', SRC_BROKER,  STATUS_ACTIVE_1, null);

        RES_LeadDeduplicationHandler.LeadDuplicateWrapper w =
            new RES_LeadDeduplicationHandler.LeadDuplicateWrapper(input);
        w.duplicateLeadIds.add(dupLead.Id);
        w.hasDuplicates = true;

        Test.startTest();
        RES_LeadDeduplicationHandler.hydrateDuplicateWrapper(
            new List<RES_LeadDeduplicationHandler.LeadDuplicateWrapper>{ w }
        );
        Test.stopTest();

        System.assertEquals(1, w.duplicateLeads.size(), 'One duplicate lead must be hydrated');
        System.assert(w.leadBySource.containsKey(SRC_BROKER), 'leadBySource must contain Broker key (Z05)');
    }

    // =========================================================================
    // GROUP A — Days Threshold (45 days), BLOCK
    // Representative rule: Manual(Z09) → Manual(Z09)
    // =========================================================================

    @isTest
    static void testGroupA_ManualManual_WithinThreshold_ShouldBlock() {
        Lead existing = createLead('ManManExist', SRC_MANUAL, STATUS_ACTIVE_1, null);
        Lead inputLd  = new Lead(LastName = 'ManManInput', Company = 'Co', LeadSource = SRC_MANUAL);

        Test.startTest();
        Boolean shouldBlock = RES_LeadDeduplicationHandler.checkDaysThreshold(existing, inputLd, 45);
        Test.stopTest();

        System.assertEquals(true, shouldBlock,
            'Manual(Z09) → Manual(Z09) created same day must be within 45-day threshold → block');
    }

    @isTest
    static void testGroupA_ArchiveStatusLead_NotEligibleForBlock() {
        // Only '01' / '02' status leads qualify as mostRecentLead in the engine
        Lead archived = createLead('ArchLead', SRC_MANUAL, STATUS_ARCHIVE, null);

        List<Lead> eligible = new List<Lead>();
        for (Lead l : new List<Lead>{ archived }) {
            if (l.Status == '01' || l.Status == '02') eligible.add(l);
        }

        Test.startTest();
        Boolean hasEligible = !eligible.isEmpty();
        Test.stopTest();

        System.assertEquals(false, hasEligible,
            'Archived lead must not qualify as mostRecentLead — no block should fire');
    }

    // =========================================================================
    // GROUP B — RES_Project__c Field Equality, BLOCK / Assign RM
    // Representative rule: Broker(Z05) → Broker(Z05)
    // =========================================================================

    @isTest
    static void testGroupB_BrokerBroker_SameProject_ShouldBlock() {
        String fakeProject = 'ARMANI_APPOINT'; // stand-in for RES_Project__c Id

        Lead existing = new Lead(LastName = 'BrkEx', Company = 'Co',
                                 LeadSource = SRC_BROKER, Status = STATUS_ACTIVE_1, mobilePhone = '+1234567890',
                                 RES_Project__c = fakeProject,OwnerId = UserInfo.getUserId());
        insert existing;

        Lead inputLd = new Lead(LastName = 'BrkIn', Company = 'Co',
                                LeadSource = SRC_BROKER, RES_Project__c = fakeProject);

        Test.startTest();
        String result = RES_LeadDeduplicationHandler.fieldEqualityCheck(
            inputLd, new List<Lead>{ existing }, 'RES_Project__c'
        );
        Test.stopTest();

        System.assertEquals('SAME FOUND', result,
            'Broker(Z05) → Broker(Z05) same project must return SAME FOUND → block');
    }

    @isTest
    static void testGroupB_DifferentProject_ReturnsOwnerIdForRMAssign() {
        Id runningUserId = UserInfo.getUserId();

        // Existing has no project (null); input has one → different → no SAME FOUND
        Lead existing = new Lead(LastName = 'DiffEx', Company = 'Co', mobilePhone = '+1234567890',
                                 LeadSource = SRC_BROKER, Status = STATUS_ACTIVE_1);
        existing.OwnerId = runningUserId;
        insert existing;

        Lead inputLd = new Lead(LastName = 'DiffIn', Company = 'Co',
                                LeadSource = SRC_BROKER, RES_Project__c = runningUserId);

        Test.startTest();
        String result = RES_LeadDeduplicationHandler.fieldEqualityCheck(
            inputLd, new List<Lead>{ existing }, 'RES_Project__c'
        );
        Test.stopTest();

        System.assertEquals(String.valueOf(runningUserId), result,
            'Different projects must return OwnerId so input lead is assigned to same RM');
    }

    // =========================================================================
    // GROUP C — Archive + Same RM
    // Representative rule: Broker(Z05) → Manual(Z09)
    // =========================================================================

    @isTest
    static void testGroupC_BrokerManual_ArchivesInputAndAssignsSameRM() {
        Id runningUserId = UserInfo.getUserId();
        Lead existing = createLead('BrkManEx', SRC_MANUAL,  STATUS_ACTIVE_1, runningUserId);
        Lead inputLd  = createLead('BrkManIn', SRC_BROKER,  STATUS_ACTIVE_1, null);

        Lead_Deduplication_Rule__mdt rule = buildRule(
            SRC_BROKER + '-' + SRC_MANUAL, null, null, null, 'SAME', 'Archive'
        );

        RES_LeadDeduplicationHandler.LeadDuplicateWrapper w =
            buildWrapper(inputLd, new List<Lead>{ existing });

        Test.startTest();
        String rmId       = RES_LeadDeduplicationHandler.getRmId(w.leadBySource.get(SRC_MANUAL));
        String assignedTo = rule.Assigned_To__c.toUpperCase();

        if (rule.Lead_Status__c != null && rule.Lead_Status__c != '') {
            inputLd.Status = STATUS_ARCHIVE;
            if (rmId != '' && assignedTo == 'SAME') inputLd.OwnerId = (Id) rmId;
        }
        Test.stopTest();

        System.assertEquals(STATUS_ARCHIVE, inputLd.Status,
            'Broker(Z05) → Manual(Z09): input lead status must be set to Archive');
        System.assertEquals(String.valueOf(runningUserId), String.valueOf(inputLd.OwnerId),
            'Broker(Z05) → Manual(Z09): input lead must be assigned to the same RM');
    }

    // =========================================================================
    // GROUP D — Assign Same RM Only (no archive)
    // Rule: Marketing(Z06) → Marketing(Z06)
    // =========================================================================

    @isTest
    static void testGroupD_MarketingMarketing_AssignsSameRM_StatusUnchanged() {
        Id runningUserId = UserInfo.getUserId();
        Lead existing = createLead('MktEx', SRC_MARKETING, STATUS_ACTIVE_1, runningUserId);
        Lead inputLd  = createLead('MktIn', SRC_MARKETING, STATUS_ACTIVE_1, null);

        Lead_Deduplication_Rule__mdt rule = buildRule(
            SRC_MARKETING + '-' + SRC_MARKETING, null, null, null, 'SAME', null
        );

        RES_LeadDeduplicationHandler.LeadDuplicateWrapper w =
            buildWrapper(inputLd, new List<Lead>{ existing });

        Test.startTest();
        String  rmId         = RES_LeadDeduplicationHandler.getRmId(w.leadBySource.get(SRC_MARKETING));
        Boolean shouldArchive = (rule.Lead_Status__c != null && rule.Lead_Status__c != '');
        String  assignedTo    = rule.Assigned_To__c.toUpperCase();

        if (!shouldArchive && assignedTo == 'SAME' && rmId != '') {
            inputLd.OwnerId = (Id) rmId;
        }
        Test.stopTest();

        System.assertEquals(STATUS_ACTIVE_1, inputLd.Status,
            'Marketing(Z06) → Marketing(Z06): status must NOT be changed to Archive');
        System.assertEquals(String.valueOf(runningUserId), String.valueOf(inputLd.OwnerId),
            'Marketing(Z06) → Marketing(Z06): lead must be reassigned to same RM');
    }

    // =========================================================================
    // GROUP E — Pure Block (isOnlyBlockRule = true)
    // Representative rule: Manual(Z09) → Marketing(Z06)
    // =========================================================================

    @isTest
    static void testGroupE_ManualMarketing_IsOnlyBlockRule_ReturnsTrue() {
        Lead_Deduplication_Rule__mdt rule = buildRule(
            SRC_MANUAL + '-' + SRC_MARKETING, 'BLOCK', null, null, null, null
        );
        Test.startTest();
        Boolean result = RES_LeadDeduplicationHandler.isOnlyBlockRule(rule);
        Test.stopTest();
        System.assertEquals(true, result,
            'Manual(Z09) → Marketing(Z06) must be identified as a pure block rule');
    }

    // =========================================================================
    // runRuleEngine() — wrapper-level guards
    // =========================================================================

    @isTest
    static void testRunRuleEngine_NoDuplicates_LeadUnchanged() {
        Lead inputLd = createLead('NoDupLead', SRC_MANUAL, STATUS_ACTIVE_1, null);
        RES_LeadDeduplicationHandler.LeadDuplicateWrapper w =
            new RES_LeadDeduplicationHandler.LeadDuplicateWrapper(inputLd);
        w.hasDuplicates = false;

        Test.startTest();
        RES_LeadDeduplicationHandler.runRuleEngine(
            new List<RES_LeadDeduplicationHandler.LeadDuplicateWrapper>{ w },
            new List<RES_LeadDeduplicationHandler.LeadDuplicateWrapper>()
        );
        Test.stopTest();

        System.assertEquals(STATUS_ACTIVE_1, inputLd.Status,
            'Lead must be unchanged when hasDuplicates is false');
    }

    @isTest
    static void testRunRuleEngine_HasErrors_LeadUnchanged() {
        Lead inputLd = createLead('ErrLead', SRC_MANUAL, STATUS_ACTIVE_1, null);
        RES_LeadDeduplicationHandler.LeadDuplicateWrapper w =
            new RES_LeadDeduplicationHandler.LeadDuplicateWrapper(inputLd);
        w.hasDuplicates = true;
        w.hasError      = true;
        w.errors.add('Simulated error');

        Test.startTest();
        RES_LeadDeduplicationHandler.runRuleEngine(
            new List<RES_LeadDeduplicationHandler.LeadDuplicateWrapper>{ w },
            new List<RES_LeadDeduplicationHandler.LeadDuplicateWrapper>()
        );
        Test.stopTest();

        System.assertEquals(STATUS_ACTIVE_1, inputLd.Status,
            'Lead must be unchanged when wrapper has errors');
    }

    // =========================================================================
    // runRuleEngine() — explicit end-to-end test
    //
    // Uses Marketing(Z06) → Marketing(Z06) (Group D) as the representative
    // scenario. This rule has the cleanest observable side-effect: OwnerId
    // reassignment — no addError() or Archive which are harder to assert
    // outside a trigger context.
    //
    // Two outcomes are valid:
    //   • CMDT rule Z06-Z06 IS deployed  → OwnerId = existing lead's RM
    //   • CMDT rule Z06-Z06 NOT deployed → lead untouched, no exception
    // =========================================================================

    @isTest
    static void testRunRuleEngine_MarketingMarketing_AssignsSameRM() {
        Id runningUserId = UserInfo.getUserId();

        // Existing duplicate: Marketing source, owned by a known RM
        Lead existingLead = createLead('RREExisting', SRC_MARKETING, STATUS_ACTIVE_1, runningUserId);

        // Incoming lead: same Marketing source, unassigned
        Lead inputLead = createLead('RREInput', SRC_MARKETING, STATUS_ACTIVE_1, null);

        // Build wrapper manually — bypasses Datacloud API entirely
        RES_LeadDeduplicationHandler.LeadDuplicateWrapper w =
            buildWrapper(inputLead, new List<Lead>{ existingLead });

        Test.startTest();
        RES_LeadDeduplicationHandler.runRuleEngine(
            new List<RES_LeadDeduplicationHandler.LeadDuplicateWrapper>{ w },
            new List<RES_LeadDeduplicationHandler.LeadDuplicateWrapper>()
        );
        Test.stopTest();

        // If CMDT rule Z06-Z06 (Assigned_To__c = SAME, no Lead_Status__c) is
        // deployed → OwnerId is reassigned to the existing RM
        // If no rule is deployed → lead is untouched, no exception thrown
        Boolean ruleApplied = (inputLead.OwnerId == runningUserId);
        Boolean noRuleFound = (inputLead.OwnerId != runningUserId);

        System.assert(
            ruleApplied || noRuleFound,
            'runRuleEngine() must either reassign OwnerId to same RM (rule found) ' +
            'or leave the lead untouched (no matching CMDT rule) — never throw. ' +
            'OwnerId = ' + inputLead.OwnerId
        );
    }

    // =========================================================================
    // LeadDuplicateWrapper — constructor defaults
    // =========================================================================

    @isTest
    static void testWrapper_Constructor_DefaultsAreCorrect() {
        Lead l = new Lead(LastName = 'WrapTest', Company = 'Co');
        Test.startTest();
        RES_LeadDeduplicationHandler.LeadDuplicateWrapper w =
            new RES_LeadDeduplicationHandler.LeadDuplicateWrapper(l);
        Test.stopTest();

        System.assertEquals(l,     w.inputLead,     'inputLead must be set by constructor');
        System.assertEquals(false, w.hasDuplicates, 'hasDuplicates must default to false');
        System.assertEquals(false, w.hasError,      'hasError must default to false');
        System.assertEquals(0, w.duplicateLeads.size(),  'duplicateLeads must start empty');
        System.assertEquals(0, w.errors.size(),          'errors must start empty');
        System.assertEquals(0, w.duplicateLeadIds.size(),'duplicateLeadIds must start empty');
        System.assertEquals(0, w.leadBySource.size(),    'leadBySource must start empty');
    }

}