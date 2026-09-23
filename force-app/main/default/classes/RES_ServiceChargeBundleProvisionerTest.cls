/*
 * SeeAllData=true is used deliberately here, not for fabricated business
 * data but because ProductRelationshipType is org-wide Revenue Cloud
 * reference/configuration data (see RES_PaymentPlanBundleProvisionerTest for
 * the same rationale), and because RES_ServiceChargeBundleProvisioner
 * resolves its Service Charge child product from the
 * RES_Service_Charge_Product_Id custom label, which points at the single,
 * real, shared Service Charge product this org already depends on (see
 * RES_ResidentialBundlePricingHook) rather than something a test should
 * fabricate.
 */
@isTest(SeeAllData=true)
private class RES_ServiceChargeBundleProvisionerTest {

    private static Id unitRecordTypeId;

    private static void setUpRecordTypeIds() {
        Map<String, Schema.RecordTypeInfo> infos = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName();
        unitRecordTypeId = infos.get('RES_Residential_Sales').getRecordTypeId();
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
        /*
         * ConfigureDuringSale = 'Allowed' is required, not optional: the real
         * shared Service Charge product (RES_Service_Charge_Product_Id) is
         * itself ConfigureDuringSale = 'Allowed', and Revenue Cloud rejects
         * adding a configurable child to a static (ConfigureDuringSale
         * blank/'Not Allowed') parent with "You can add only static products
         * as child components of a static parent product." Matches how
         * RES_UnifiedIngestionEngine actually creates every Unit.
         */
        Product2 unit = new Product2(
            Name = 'Test Unit',
            IsActive = true,
            RecordTypeId = unitRecordTypeId,
            RES_Business_Entity__c = catalogId,
            Type = 'Bundle',
            ConfigureDuringSale = 'Allowed'
        );
        insert unit;
        return unit;
    }

    private static Id serviceChargeProductId() {
        return Id.valueOf(System.Label.RES_Service_Charge_Product_Id);
    }

    @isTest
    static void provisionsGroupAndComponentForEachUnit() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Product2 unit1 = createUnit(catalog.Id);
        Product2 unit2 = createUnit(catalog.Id);

        Test.startTest();
        RES_ServiceChargeBundleProvisioner.provisionForUnits(new Set<Id>{ unit1.Id, unit2.Id });
        Test.stopTest();

        List<ProductComponentGroup> groups = [
            SELECT Id, ParentProductId, Code, Name, Sequence, MinBundleComponents, MaxBundleComponents
            FROM ProductComponentGroup
            WHERE ParentProductId IN :new Set<Id>{ unit1.Id, unit2.Id }
        ];
        System.assertEquals(2, groups.size(), 'Expected one ProductComponentGroup per unit');
        for (ProductComponentGroup componentGroup : groups) {
            System.assertEquals(componentGroup.ParentProductId + '-SC', componentGroup.Code);
            System.assertEquals('Service Charge', componentGroup.Name);
            System.assertEquals(1, componentGroup.MinBundleComponents);
            System.assertEquals(1, componentGroup.MaxBundleComponents);
        }

        Id serviceChargeId = serviceChargeProductId();
        List<ProductRelatedComponent> components = [
            SELECT Id, ParentProductId, ChildProductId, ProductComponentGroupId, ProductRelationshipTypeId,
                   IsComponentRequired, IsDefaultComponent, DoesBundlePriceIncludeChild, QuoteVisibility
            FROM ProductRelatedComponent
            WHERE ParentProductId IN :new Set<Id>{ unit1.Id, unit2.Id } AND ChildProductId = :serviceChargeId
        ];
        System.assertEquals(2, components.size(), 'Expected one component per unit linking to the shared Service Charge product');
        for (ProductRelatedComponent component : components) {
            System.assertNotEquals(null, component.ProductComponentGroupId);
            System.assertNotEquals(null, component.ProductRelationshipTypeId);
            System.assertEquals(true, component.IsComponentRequired);
            System.assertEquals(true, component.IsDefaultComponent);
            System.assertEquals(false, component.DoesBundlePriceIncludeChild);
            System.assertEquals('Always', component.QuoteVisibility);
        }
    }

    @isTest
    static void isIdempotentAndSkipsExistingGroupAndComponent() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Product2 unit = createUnit(catalog.Id);

        Test.startTest();
        RES_ServiceChargeBundleProvisioner.provisionForUnits(new Set<Id>{ unit.Id });
        RES_ServiceChargeBundleProvisioner.provisionForUnits(new Set<Id>{ unit.Id });
        Test.stopTest();

        List<ProductComponentGroup> groups = [SELECT Id FROM ProductComponentGroup WHERE ParentProductId = :unit.Id];
        System.assertEquals(1, groups.size(), 'Second run must not create a duplicate group');

        Id serviceChargeId = serviceChargeProductId();
        List<ProductRelatedComponent> components = [
            SELECT Id FROM ProductRelatedComponent WHERE ParentProductId = :unit.Id AND ChildProductId = :serviceChargeId
        ];
        System.assertEquals(1, components.size(), 'Second run must not create a duplicate component');
    }

    @isTest
    static void handlesNullAndEmptySetsGracefully() {
        Test.startTest();
        RES_ServiceChargeBundleProvisioner.provisionForUnits(null);
        RES_ServiceChargeBundleProvisioner.provisionForUnits(new Set<Id>());
        Test.stopTest();
    }
}
