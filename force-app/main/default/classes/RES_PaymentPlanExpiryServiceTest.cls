/*
 * SeeAllData=true for the same reason as RES_PaymentPlanBundleProvisionerTest: ProductRelationshipType is
 * org-wide Revenue Cloud reference data that a test should not fabricate. Every record this test creates is
 * rolled back when the test ends. Batch scope is built from the test's own Units (not the QueryLocator) so
 * real org data cannot interfere.
 */
@isTest(SeeAllData=true)
private class RES_PaymentPlanExpiryServiceTest {

    private static final Date TODAY = Date.newInstance(2026, 10, 8);

    private static Id unitRecordTypeId;
    private static Id paymentPlanRecordTypeId;
    private static Id relationshipTypeId;

    private static void setUp() {
        RES_IntegrationRequestEventService.batchSubmitter = new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        Map<String, Schema.RecordTypeInfo> infos = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName();
        unitRecordTypeId = infos.get('RES_Residential_Sales').getRecordTypeId();
        paymentPlanRecordTypeId = infos.get('RES_Residential_Payment_Plan').getRecordTypeId();
        relationshipTypeId = [SELECT Id FROM ProductRelationshipType WHERE Name = 'Bundle to Bundle Component Relationship' LIMIT 1].Id;
    }

    private static Product2 createUnit(String name) {
        Product2 unit = new Product2(Name = name, IsActive = true, RecordTypeId = unitRecordTypeId, Type = 'Bundle', ConfigureDuringSale = 'Allowed');
        insert unit;
        return unit;
    }

    private static Product2 createPlan(String name, Date validityEnd, Boolean isActive) {
        Product2 plan = new Product2(
            Name = name, IsActive = isActive, RecordTypeId = paymentPlanRecordTypeId, RES_Validity_End_Date__c = validityEnd
        );
        insert plan;
        return plan;
    }

    private static ProductComponentGroup createGroup(Product2 unit) {
        ProductComponentGroup componentGroup = new ProductComponentGroup(
            ParentProductId = unit.Id,
            Name = RES_PaymentPlanBundleProvisioner.GROUP_NAME,
            Code = unit.Id + '-PP',
            Sequence = 10,
            MinBundleComponents = 1,
            MaxBundleComponents = 1
        );
        insert componentGroup;
        return componentGroup;
    }

    private static ProductRelatedComponent createComponent(Product2 unit, ProductComponentGroup componentGroup, Product2 plan, Boolean isDefault) {
        ProductRelatedComponent component = new ProductRelatedComponent(
            ParentProductId = unit.Id,
            ChildProductId = plan.Id,
            ProductComponentGroupId = componentGroup.Id,
            ProductRelationshipTypeId = relationshipTypeId,
            Quantity = 1,
            IsComponentRequired = false,
            IsDefaultComponent = isDefault,
            IsQuantityEditable = false,
            DoesBundlePriceIncludeChild = false,
            QuoteVisibility = 'Always'
        );
        insert component;
        return component;
    }

    private static Map<Id, ProductRelatedComponent> componentsById(Id unitId) {
        return new Map<Id, ProductRelatedComponent>([
            SELECT Id, ChildProductId, IsDefaultComponent FROM ProductRelatedComponent WHERE ParentProductId = :unitId
        ]);
    }

    @isTest
    static void expiredDefaultIsDeletedAndFirstRemainingBecomesDefault() {
        setUp();
        Product2 unit = createUnit('Expiry Unit 1');
        ProductComponentGroup componentGroup = createGroup(unit);
        Product2 expiredPlan = createPlan('Expired Plan', TODAY.addDays(-1), true);
        Product2 plan2 = createPlan('Plan 2', TODAY.addDays(30), true);
        Product2 plan3 = createPlan('Plan 3', null, true);
        ProductRelatedComponent expiredPrc = createComponent(unit, componentGroup, expiredPlan, true);
        ProductRelatedComponent prc2 = createComponent(unit, componentGroup, plan2, false);
        ProductRelatedComponent prc3 = createComponent(unit, componentGroup, plan3, false);

        Test.startTest();
        RES_PaymentPlanExpiryService.Result result = RES_PaymentPlanExpiryService.process(new Set<Id>{ unit.Id }, TODAY, false);
        Test.stopTest();

        Map<Id, ProductRelatedComponent> remaining = componentsById(unit.Id);
        System.assertEquals(2, remaining.size(), 'Expired component must be deleted');
        System.assertEquals(false, remaining.containsKey(expiredPrc.Id));
        System.assertEquals(true, remaining.get(prc2.Id).IsDefaultComponent, 'First remaining component becomes the default');
        System.assertEquals(false, remaining.get(prc3.Id).IsDefaultComponent, 'Only one default per Unit');
        System.assertEquals(1, result.componentsDeleted);
        System.assertEquals(1, result.defaultsDemoted);
        System.assertEquals(1, result.defaultsPromoted);
        System.assertEquals(0, result.failures);
    }

    @isTest
    static void expiredNonDefaultIsDeletedWithoutTouchingTheDefault() {
        setUp();
        Product2 unit = createUnit('Expiry Unit 2');
        ProductComponentGroup componentGroup = createGroup(unit);
        Product2 defaultPlan = createPlan('Default Plan', TODAY.addDays(10), true);
        Product2 expiredPlan = createPlan('Expired Plan', TODAY.addDays(-5), true);
        ProductRelatedComponent defaultPrc = createComponent(unit, componentGroup, defaultPlan, true);
        ProductRelatedComponent expiredPrc = createComponent(unit, componentGroup, expiredPlan, false);

        Test.startTest();
        RES_PaymentPlanExpiryService.Result result = RES_PaymentPlanExpiryService.process(new Set<Id>{ unit.Id }, TODAY, false);
        Test.stopTest();

        Map<Id, ProductRelatedComponent> remaining = componentsById(unit.Id);
        System.assertEquals(1, remaining.size());
        System.assertEquals(true, remaining.get(defaultPrc.Id).IsDefaultComponent);
        System.assertEquals(0, result.defaultsDemoted);
        System.assertEquals(0, result.defaultsPromoted);
        System.assertEquals(1, result.componentsDeleted);
    }

    @isTest
    static void promotionSkipsInactiveAndOtherExpiredPlans() {
        setUp();
        Product2 unit = createUnit('Expiry Unit 3');
        ProductComponentGroup componentGroup = createGroup(unit);
        Product2 expiredDefault = createPlan('Expired Default', TODAY.addDays(-1), true);
        Product2 expiredOther = createPlan('Expired Other', TODAY.addDays(-2), true);
        Product2 inactivePlan = createPlan('Inactive Plan', null, false);
        Product2 goodPlan = createPlan('Good Plan', null, true);
        createComponent(unit, componentGroup, expiredDefault, true);
        createComponent(unit, componentGroup, expiredOther, false);
        createComponent(unit, componentGroup, inactivePlan, false);
        ProductRelatedComponent goodPrc = createComponent(unit, componentGroup, goodPlan, false);

        Test.startTest();
        RES_PaymentPlanExpiryService.process(new Set<Id>{ unit.Id }, TODAY, false);
        Test.stopTest();

        Map<Id, ProductRelatedComponent> remaining = componentsById(unit.Id);
        System.assertEquals(2, remaining.size(), 'Both expired components deleted; inactive plan component stays');
        System.assertEquals(true, remaining.get(goodPrc.Id).IsDefaultComponent, 'Active, non-expired plan is promoted');
    }

    @isTest
    static void lastRemainingComponentExpiredLeavesUnitWithNoDefaultAndNoError() {
        setUp();
        Product2 unit = createUnit('Expiry Unit 4');
        ProductComponentGroup componentGroup = createGroup(unit);
        Product2 expiredPlan = createPlan('Expired Plan', TODAY.addDays(-1), true);
        createComponent(unit, componentGroup, expiredPlan, true);

        Test.startTest();
        RES_PaymentPlanExpiryService.Result result = RES_PaymentPlanExpiryService.process(new Set<Id>{ unit.Id }, TODAY, false);
        Test.stopTest();

        System.assertEquals(0, componentsById(unit.Id).size());
        System.assertEquals(1, result.componentsDeleted);
        System.assertEquals(0, result.defaultsPromoted);
        System.assertEquals(0, result.failures);
    }

    @isTest
    static void planEndingTodayIsNotExpiredYet() {
        setUp();
        Product2 unit = createUnit('Expiry Unit 5');
        ProductComponentGroup componentGroup = createGroup(unit);
        Product2 endsToday = createPlan('Ends Today', TODAY, true);
        createComponent(unit, componentGroup, endsToday, true);

        Test.startTest();
        RES_PaymentPlanExpiryService.Result result = RES_PaymentPlanExpiryService.process(new Set<Id>{ unit.Id }, TODAY, false);
        Test.stopTest();

        System.assertEquals(1, componentsById(unit.Id).size());
        System.assertEquals(0, result.componentsDeleted);
    }

    @isTest
    static void dryRunReportsButChangesNothing() {
        setUp();
        Product2 unit = createUnit('Expiry Unit 6');
        ProductComponentGroup componentGroup = createGroup(unit);
        Product2 expiredPlan = createPlan('Expired Plan', TODAY.addDays(-1), true);
        Product2 plan2 = createPlan('Plan 2', null, true);
        ProductRelatedComponent expiredPrc = createComponent(unit, componentGroup, expiredPlan, true);
        ProductRelatedComponent prc2 = createComponent(unit, componentGroup, plan2, false);

        Test.startTest();
        RES_PaymentPlanExpiryService.Result result = RES_PaymentPlanExpiryService.process(new Set<Id>{ unit.Id }, TODAY, true);
        Test.stopTest();

        Map<Id, ProductRelatedComponent> remaining = componentsById(unit.Id);
        System.assertEquals(2, remaining.size(), 'Dry run must not delete');
        System.assertEquals(true, remaining.get(expiredPrc.Id).IsDefaultComponent, 'Dry run must not demote');
        System.assertEquals(false, remaining.get(prc2.Id).IsDefaultComponent, 'Dry run must not promote');
        System.assertEquals(1, result.componentsDeleted, 'Dry run still reports what it would delete');
    }

    @isTest
    static void batchExecuteProcessesUnitsFromScope() {
        setUp();
        Product2 unit = createUnit('Expiry Unit 7');
        ProductComponentGroup componentGroup = createGroup(unit);
        Product2 expiredPlan = createPlan('Expired Plan', Date.today().addDays(-1), true);
        Product2 plan2 = createPlan('Plan 2', null, true);
        ProductRelatedComponent expiredPrc = createComponent(unit, componentGroup, expiredPlan, true);
        ProductRelatedComponent prc2 = createComponent(unit, componentGroup, plan2, false);

        List<ProductRelatedComponent> scope = [SELECT Id, ParentProductId FROM ProductRelatedComponent WHERE Id = :expiredPrc.Id];

        Test.startTest();
        RES_PaymentPlanExpiryBatch batch = new RES_PaymentPlanExpiryBatch();
        System.assertNotEquals(null, batch.start(null), 'start() must return a locator');
        batch.execute(null, scope);
        batch.finish(null);
        Test.stopTest();

        Map<Id, ProductRelatedComponent> remaining = componentsById(unit.Id);
        System.assertEquals(1, remaining.size());
        System.assertEquals(true, remaining.get(prc2.Id).IsDefaultComponent);
    }

    /*
     * Forced-failure DML: SaveResult / DeleteResult cannot be constructed directly, so they are built
     * from JSON. The stub can fail updates and/or deletes; whatever it does not fail runs for real.
     */
    private static final String FAILURE_JSON = '{"success":false,"errors":[{"message":"forced failure","statusCode":"FIELD_CUSTOM_VALIDATION_EXCEPTION","fields":[]}]}';

    private class FailingDml extends RES_PaymentPlanExpiryService.DmlGateway {
        private Boolean failUpdates;
        private Boolean failDeletes;
        FailingDml(Boolean failUpdates, Boolean failDeletes) {
            this.failUpdates = failUpdates;
            this.failDeletes = failDeletes;
        }
        public override List<Database.SaveResult> updateRecords(List<SObject> records) {
            if (!failUpdates) {
                return super.updateRecords(records);
            }
            List<Database.SaveResult> results = new List<Database.SaveResult>();
            for (SObject record : records) {
                results.add((Database.SaveResult) JSON.deserialize(FAILURE_JSON, Database.SaveResult.class));
            }
            return results;
        }
        public override List<Database.DeleteResult> deleteRecords(List<SObject> records) {
            if (!failDeletes) {
                return super.deleteRecords(records);
            }
            List<Database.DeleteResult> results = new List<Database.DeleteResult>();
            for (SObject record : records) {
                results.add((Database.DeleteResult) JSON.deserialize(FAILURE_JSON, Database.DeleteResult.class));
            }
            return results;
        }
    }

    @isTest
    static void failedPromotionKeepsExpiredComponentsSoTheNextRunRetries() {
        setUp();
        Product2 unit = createUnit('Expiry Unit Fail 1');
        ProductComponentGroup componentGroup = createGroup(unit);
        Product2 expiredPlan = createPlan('Expired Plan', TODAY.addDays(-1), true);
        Product2 plan2 = createPlan('Plan 2', null, true);
        ProductRelatedComponent expiredPrc = createComponent(unit, componentGroup, expiredPlan, true);
        createComponent(unit, componentGroup, plan2, false);
        RES_PaymentPlanExpiryService.dml = new FailingDml(true, false);

        Test.startTest();
        RES_PaymentPlanExpiryService.Result result = RES_PaymentPlanExpiryService.process(new Set<Id>{ unit.Id }, TODAY, false);
        Test.stopTest();

        System.assertEquals(2, componentsById(unit.Id).size(), 'Nothing is deleted while the replacement default could not be set');
        System.assertEquals(true, componentsById(unit.Id).containsKey(expiredPrc.Id));
        System.assertEquals(0, result.componentsDeleted);
        System.assertEquals(2, result.failures, 'Demotion and promotion both reported as failures');
    }

    @isTest
    static void failedDeleteIsCountedAndNotReportedAsDeleted() {
        setUp();
        Product2 unit = createUnit('Expiry Unit Fail 2');
        ProductComponentGroup componentGroup = createGroup(unit);
        Product2 expiredPlan = createPlan('Expired Plan', TODAY.addDays(-1), true);
        Product2 plan2 = createPlan('Plan 2', null, true);
        createComponent(unit, componentGroup, expiredPlan, true);
        createComponent(unit, componentGroup, plan2, false);
        RES_PaymentPlanExpiryService.dml = new FailingDml(false, true);

        Test.startTest();
        RES_PaymentPlanExpiryService.Result result = RES_PaymentPlanExpiryService.process(new Set<Id>{ unit.Id }, TODAY, false);
        Test.stopTest();

        System.assertEquals(2, componentsById(unit.Id).size(), 'Forced delete failure leaves both components');
        System.assertEquals(0, result.componentsDeleted);
        System.assertEquals(1, result.failures);
        System.assertEquals(1, result.defaultsPromoted, 'Promotion itself succeeded');
    }

    @isTest
    static void schedulableExecuteEnqueuesBatch() {
        Test.startTest();
        String jobId = System.schedule('RES Payment Plan Expiry Test', '0 0 1 * * ?', new RES_PaymentPlanExpiryBatch());
        System.assertNotEquals(null, jobId);
        // dry run so the batch the schedule enqueues cannot change any org data
        new RES_PaymentPlanExpiryBatch(true).execute((SchedulableContext) null);
        Test.stopTest();
    }

    @isTest
    static void staticParentUnitStillDeletesExpiredComponent() {
        setUp();
        Product2 unit = new Product2(Name = 'Static Unit', IsActive = true, RecordTypeId = unitRecordTypeId, Type = 'Bundle', ConfigureDuringSale = 'NotAllowed');
        insert unit;
        ProductComponentGroup componentGroup = createGroup(unit);
        Product2 expiredPlan = createPlan('Expired Plan', TODAY.addDays(-1), true);
        createComponent(unit, componentGroup, expiredPlan, true);

        Test.startTest();
        RES_PaymentPlanExpiryService.Result result = RES_PaymentPlanExpiryService.process(new Set<Id>{ unit.Id }, TODAY, false);
        Test.stopTest();

        System.assertEquals(0, componentsById(unit.Id).size(), 'A rejected demotion on a Static parent must not block the delete');
        System.assertEquals(1, result.componentsDeleted);
    }

    @isTest
    static void handlesNullAndEmptyInputsGracefully() {
        RES_PaymentPlanExpiryService.Result nullResult = RES_PaymentPlanExpiryService.process(null, TODAY, false);
        RES_PaymentPlanExpiryService.Result emptyResult = RES_PaymentPlanExpiryService.process(new Set<Id>(), TODAY, false);
        System.assertEquals(0, nullResult.unitsProcessed);
        System.assertEquals(0, emptyResult.unitsProcessed);
    }
}
