/*
 * SeeAllData=true is used deliberately here, not for fabricated business
 * data but because ProductRelationshipType is org-wide Revenue Cloud
 * reference/configuration data (its Main+Associated Product Role Category
 * combination is globally unique per org, same category as RecordType or
 * BusinessHours) rather than something a test should fabricate. The real
 * "Bundle to Bundle Component Relationship" row this org already depends
 * on for its live bundle pricing (see RES_ResidentialBundlePricingHook) is
 * exactly what RES_PaymentPlanBundleProvisioner resolves by name at
 * runtime, so exercising the real one is the correct thing to test against.
 */
@isTest(SeeAllData=true)
private class RES_PaymentPlanBundleProvisionerTest {

    private static Id unitRecordTypeId;
    private static Id paymentPlanRecordTypeId;

    private static void setUpRecordTypeIds() {
        RES_IntegrationRequestEventService.batchSubmitter = new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        Map<String, Schema.RecordTypeInfo> infos = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName();
        unitRecordTypeId = infos.get('RES_Residential_Sales').getRecordTypeId();
        paymentPlanRecordTypeId = infos.get('RES_Residential_Payment_Plan').getRecordTypeId();
    }

    /*
     * ProductCatalog insert fires RES_ProductCatalogTrigger, which (when
     * triggers are enabled) syncs to the SAP integration queueable - unrelated
     * to bundle provisioning and prone to failing here for its own
     * environment/config reasons (Named Credential, etc.). Trigger toggling
     * is scoped tightly to just this insert and restored immediately after,
     * matching the RES_Config_Switch__c.RES_Triggers_Off__c framework
     * convention already used by RES_ProductCatalogTrigger itself. Safe
     * under SeeAllData=true because all test-method DML, including Custom
     * Setting changes, is rolled back automatically when the test ends.
     */
    private static ProductCatalog createCatalog() {
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        Boolean wasOff = config.RES_Triggers_Off__c;
        config.RES_Triggers_Off__c = true;
        upsert config;

        ProductCatalog catalog = new ProductCatalog(Name = 'Test Catalog');
        insert catalog;

        config.RES_Triggers_Off__c = wasOff;
        upsert config;
        return catalog;
    }

    private static Product2 createUnit(Id catalogId) {
        return createUnit(catalogId, true);
    }

    private static Product2 createUnit(Id catalogId, Boolean isActive) {
        Product2 unit = new Product2(
            Name = 'Test Unit',
            IsActive = isActive,
            RecordTypeId = unitRecordTypeId,
            RES_Business_Entity__c = catalogId,
            Type = 'Bundle',
            ConfigureDuringSale = 'Allowed'
        );
        insert unit;
        return unit;
    }

    private static Product2 createPaymentPlan(Id catalogId) {
        Product2 plan = new Product2(
            Name = 'Test Payment Plan',
            IsActive = true,
            RecordTypeId = paymentPlanRecordTypeId,
            RES_Business_Entity__c = catalogId,
            RES_Price_Option__c = 'Test Price Option'
        );
        insert plan;
        return plan;
    }

    @isTest
    static void provisionsGroupAndComponentForEachUnitInCatalog() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Product2 unit1 = createUnit(catalog.Id);
        Product2 unit2 = createUnit(catalog.Id);
        Product2 plan = createPaymentPlan(catalog.Id);

        RES_PaymentPlanBundleProvisioner.Request req = new RES_PaymentPlanBundleProvisioner.Request();
        req.paymentPlanId = plan.Id;

        Test.startTest();
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>{ req });
        Test.stopTest();

        List<ProductComponentGroup> groups = [
            SELECT Id, ParentProductId, Code, Name, Sequence, MinBundleComponents, MaxBundleComponents
            FROM ProductComponentGroup
            WHERE ParentProductId IN :new Set<Id>{ unit1.Id, unit2.Id }
        ];
        System.assertEquals(2, groups.size(), 'Expected one ProductComponentGroup per unit');
        for (ProductComponentGroup componentGroup : groups) {
            System.assertEquals(componentGroup.ParentProductId + '-PP', componentGroup.Code);
            System.assertEquals('Payment Plan', componentGroup.Name);
            System.assertEquals(1, componentGroup.MinBundleComponents);
            System.assertEquals(1, componentGroup.MaxBundleComponents);
        }

        List<ProductRelatedComponent> components = [
            SELECT Id, ParentProductId, ChildProductId, ProductComponentGroupId, ProductRelationshipTypeId, RES_Price_Option__c
            FROM ProductRelatedComponent
            WHERE ChildProductId = :plan.Id
        ];
        System.assertEquals(2, components.size(), 'Expected one component per unit linking to the plan');
        for (ProductRelatedComponent component : components) {
            System.assertNotEquals(null, component.ProductComponentGroupId);
            System.assertNotEquals(null, component.ProductRelationshipTypeId);
            System.assertEquals('Test Price Option', component.RES_Price_Option__c,
                'RES_ResidentialBundlePricingHook prices the Unit off this field - it must be carried over from the Payment Plan');
        }
    }

    @isTest
    static void provisionsInactiveUnitsToo() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Product2 activeUnit = createUnit(catalog.Id);
        Product2 inactiveUnit = createUnit(catalog.Id, false);
        Product2 plan = createPaymentPlan(catalog.Id);

        RES_PaymentPlanBundleProvisioner.Request req = new RES_PaymentPlanBundleProvisioner.Request();
        req.paymentPlanId = plan.Id;

        Test.startTest();
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM ProductComponentGroup WHERE ParentProductId = :inactiveUnit.Id],
            'DIR-1907: an inactive Unit must still get a Payment Plan group');
        System.assertEquals(1, [SELECT COUNT() FROM ProductRelatedComponent WHERE ParentProductId = :inactiveUnit.Id AND ChildProductId = :plan.Id],
            'DIR-1907: an inactive Unit must still get tagged with the Payment Plan');
    }

    @isTest
    static void isIdempotentAndSkipsExistingGroupAndComponent() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Product2 unit = createUnit(catalog.Id);
        Product2 plan = createPaymentPlan(catalog.Id);

        RES_PaymentPlanBundleProvisioner.Request req = new RES_PaymentPlanBundleProvisioner.Request();
        req.paymentPlanId = plan.Id;

        Test.startTest();
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>{ req });
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>{ req });
        Test.stopTest();

        List<ProductComponentGroup> groups = [SELECT Id FROM ProductComponentGroup WHERE ParentProductId = :unit.Id];
        System.assertEquals(1, groups.size(), 'Second run must not create a duplicate group');

        List<ProductRelatedComponent> components = [SELECT Id FROM ProductRelatedComponent WHERE ChildProductId = :plan.Id];
        System.assertEquals(1, components.size(), 'Second run must not create a duplicate component');
    }

    @isTest
    static void doesNothingWhenPaymentPlanHasNoCatalog() {
        setUpRecordTypeIds();
        Product2 plan = new Product2(Name = 'Untagged Plan', IsActive = true, RecordTypeId = paymentPlanRecordTypeId);
        insert plan;

        RES_PaymentPlanBundleProvisioner.Request req = new RES_PaymentPlanBundleProvisioner.Request();
        req.paymentPlanId = plan.Id;

        Test.startTest();
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>{ req });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ProductRelatedComponent WHERE ChildProductId = :plan.Id]);
    }

    @isTest
    static void secondPlanIsNotDefaultWhenUnitAlreadyHasADefault() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Product2 unit = createUnit(catalog.Id);
        Product2 firstPlan = createPaymentPlan(catalog.Id);
        Product2 secondPlan = createPaymentPlan(catalog.Id);

        Test.startTest();
        RES_PaymentPlanBundleProvisioner.Request firstReq = new RES_PaymentPlanBundleProvisioner.Request();
        firstReq.paymentPlanId = firstPlan.Id;
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>{ firstReq });
        RES_PaymentPlanBundleProvisioner.Request secondReq = new RES_PaymentPlanBundleProvisioner.Request();
        secondReq.paymentPlanId = secondPlan.Id;
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>{ secondReq });
        Test.stopTest();

        Map<Id, ProductRelatedComponent> byPlan = new Map<Id, ProductRelatedComponent>();
        for (ProductRelatedComponent component : [
            SELECT Id, ChildProductId, IsDefaultComponent FROM ProductRelatedComponent WHERE ParentProductId = :unit.Id
        ]) {
            byPlan.put(component.ChildProductId, component);
        }
        System.assertEquals(2, byPlan.size());
        System.assertEquals(true, byPlan.get(firstPlan.Id).IsDefaultComponent, 'First plan on a Unit with no default becomes the default');
        System.assertEquals(false, byPlan.get(secondPlan.Id).IsDefaultComponent, 'A Unit may only have one default Payment Plan');
    }

    @isTest
    static void planBecomesDefaultOnlyOnUnitsWithoutOne() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Product2 unitWithDefault = createUnit(catalog.Id);
        Product2 existingPlan = createPaymentPlan(catalog.Id);

        RES_PaymentPlanBundleProvisioner.Request existingReq = new RES_PaymentPlanBundleProvisioner.Request();
        existingReq.paymentPlanId = existingPlan.Id;
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>{ existingReq });

        Product2 newUnit = createUnit(catalog.Id);
        Product2 newPlan = createPaymentPlan(catalog.Id);
        RES_PaymentPlanBundleProvisioner.Request newReq = new RES_PaymentPlanBundleProvisioner.Request();
        newReq.paymentPlanId = newPlan.Id;

        Test.startTest();
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>{ newReq });
        Test.stopTest();

        ProductRelatedComponent onUnitWithDefault = [
            SELECT IsDefaultComponent FROM ProductRelatedComponent WHERE ParentProductId = :unitWithDefault.Id AND ChildProductId = :newPlan.Id
        ];
        ProductRelatedComponent onNewUnit = [
            SELECT IsDefaultComponent FROM ProductRelatedComponent WHERE ParentProductId = :newUnit.Id AND ChildProductId = :newPlan.Id
        ];
        System.assertEquals(false, onUnitWithDefault.IsDefaultComponent, 'Unit already had a default');
        System.assertEquals(true, onNewUnit.IsDefaultComponent, 'Unit with no default gets this plan as default');
    }

    @isTest
    static void staticParentUnitKeepsEveryPlanAsDefaultInsteadOfLosingIt() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Product2 staticUnit = new Product2(
            Name = 'Static Test Unit', IsActive = true, RecordTypeId = unitRecordTypeId,
            RES_Business_Entity__c = catalog.Id, Type = 'Bundle', ConfigureDuringSale = 'NotAllowed'
        );
        insert staticUnit;
        Product2 firstPlan = createPaymentPlan(catalog.Id);
        Product2 secondPlan = createPaymentPlan(catalog.Id);

        Test.startTest();
        RES_PaymentPlanBundleProvisioner.Request firstReq = new RES_PaymentPlanBundleProvisioner.Request();
        firstReq.paymentPlanId = firstPlan.Id;
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>{ firstReq });
        RES_PaymentPlanBundleProvisioner.Request secondReq = new RES_PaymentPlanBundleProvisioner.Request();
        secondReq.paymentPlanId = secondPlan.Id;
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>{ secondReq });
        Test.stopTest();

        List<ProductRelatedComponent> components = [
            SELECT ChildProductId, IsDefaultComponent FROM ProductRelatedComponent WHERE ParentProductId = :staticUnit.Id
        ];
        System.assertEquals(2, components.size(), 'A Static parent rejects non-default components; the plan must be retried as default, not dropped');
        for (ProductRelatedComponent component : components) {
            System.assertEquals(true, component.IsDefaultComponent);
        }
    }

    @isTest
    static void recognisesOnlyTheStaticParentPlatformMessage() {
        System.assertEquals(true, RES_PaymentPlanBundleProvisioner.isStaticParentMessage(
            'Child component must be added by default for a Static Parent Product.'));
        System.assertEquals(false, RES_PaymentPlanBundleProvisioner.isStaticParentMessage('Some other validation failed'));
        System.assertEquals(false, RES_PaymentPlanBundleProvisioner.isStaticParentMessage(null));
    }

    /*
     * Forced-failure inserts: SaveResult cannot be constructed directly, so it is built from JSON.
     * failGroups fails ProductComponentGroup inserts; failComponents fails every ProductRelatedComponent
     * insert (including the retry) with the given message. Anything not failed runs for real.
     */
    private class FailingDml extends RES_PaymentPlanBundleProvisioner.DmlGateway {
        private Boolean failGroups;
        private String componentFailureMessage;
        FailingDml(Boolean failGroups, String componentFailureMessage) {
            this.failGroups = failGroups;
            this.componentFailureMessage = componentFailureMessage;
        }
        public override List<Database.SaveResult> insertRecords(List<SObject> records) {
            Boolean isGroup = records[0] instanceof ProductComponentGroup;
            if ((isGroup && !failGroups) || (!isGroup && componentFailureMessage == null)) {
                return super.insertRecords(records);
            }
            String message = isGroup ? 'forced group failure' : componentFailureMessage;
            String resultJson = '{"success":false,"errors":[{"message":"' + message + '","statusCode":"FIELD_CUSTOM_VALIDATION_EXCEPTION","fields":[]}]}';
            List<Database.SaveResult> results = new List<Database.SaveResult>();
            for (SObject record : records) {
                results.add((Database.SaveResult) JSON.deserialize(resultJson, Database.SaveResult.class));
            }
            return results;
        }
    }

    private static void provisionPlan(Id planId) {
        RES_PaymentPlanBundleProvisioner.Request req = new RES_PaymentPlanBundleProvisioner.Request();
        req.paymentPlanId = planId;
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>{ req });
    }

    @isTest
    static void doesNothingWhenCatalogHasNoUnits() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Product2 plan = createPaymentPlan(catalog.Id);

        Test.startTest();
        provisionPlan(plan.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ProductRelatedComponent WHERE ChildProductId = :plan.Id]);
    }

    @isTest
    static void abortsWhenRelationshipTypeCannotBeFound() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Product2 unit = createUnit(catalog.Id);
        Product2 plan = createPaymentPlan(catalog.Id);
        RES_PaymentPlanBundleProvisioner.relationshipTypeName = 'No Such Relationship Type';

        Test.startTest();
        provisionPlan(plan.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ProductComponentGroup WHERE ParentProductId = :unit.Id], 'Nothing is created without a relationship type');
        System.assertEquals(0, [SELECT COUNT() FROM ProductRelatedComponent WHERE ChildProductId = :plan.Id]);
    }

    @isTest
    static void skipsComponentWhenItsGroupCouldNotBeCreated() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Product2 unit = createUnit(catalog.Id);
        Product2 plan = createPaymentPlan(catalog.Id);
        RES_PaymentPlanBundleProvisioner.dml = new FailingDml(true, null);

        Test.startTest();
        provisionPlan(plan.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ProductComponentGroup WHERE ParentProductId = :unit.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM ProductRelatedComponent WHERE ChildProductId = :plan.Id], 'No group, so no component');
    }

    @isTest
    static void nonStaticComponentFailureIsLoggedAndNotRetried() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Product2 unit = createUnit(catalog.Id);
        Product2 firstPlan = createPaymentPlan(catalog.Id);
        Product2 secondPlan = createPaymentPlan(catalog.Id);
        provisionPlan(firstPlan.Id);
        RES_PaymentPlanBundleProvisioner.dml = new FailingDml(false, 'forced component failure');

        Test.startTest();
        provisionPlan(secondPlan.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ProductRelatedComponent WHERE ChildProductId = :secondPlan.Id],
            'A failure that is not the Static-parent rule must not be retried as default');
        System.assertEquals(1, [SELECT COUNT() FROM ProductRelatedComponent WHERE ParentProductId = :unit.Id AND IsDefaultComponent = true]);
    }

    @isTest
    static void failedRetryAsDefaultIsLoggedWithoutError() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Product2 unit = createUnit(catalog.Id);
        Product2 firstPlan = createPaymentPlan(catalog.Id);
        Product2 secondPlan = createPaymentPlan(catalog.Id);
        provisionPlan(firstPlan.Id);
        RES_PaymentPlanBundleProvisioner.dml = new FailingDml(false, 'Child component must be added by default for a Static Parent Product.');

        Test.startTest();
        provisionPlan(secondPlan.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ProductRelatedComponent WHERE ChildProductId = :secondPlan.Id],
            'Both the first attempt and the retry were forced to fail');
        System.assertEquals(1, [SELECT COUNT() FROM ProductRelatedComponent WHERE ParentProductId = :unit.Id]);
    }

    @isTest
    static void handlesNullAndEmptyRequestsGracefully() {
        Test.startTest();
        RES_PaymentPlanBundleProvisioner.provision(null);
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>());
        Test.stopTest();
    }
}