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
        Product2 unit = new Product2(
            Name = 'Test Unit',
            IsActive = true,
            RecordTypeId = unitRecordTypeId,
            RES_Business_Entity__c = catalogId,
            Type = 'Bundle'
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
    static void handlesNullAndEmptyRequestsGracefully() {
        Test.startTest();
        RES_PaymentPlanBundleProvisioner.provision(null);
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>());
        Test.stopTest();
    }
}