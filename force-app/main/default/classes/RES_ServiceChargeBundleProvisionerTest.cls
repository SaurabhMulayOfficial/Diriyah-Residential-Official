@isTest
private class RES_ServiceChargeBundleProvisionerTest {

    private static Id unitRecordTypeId;

    @testSetup
    static void setUpReferenceData() {
        // Org reference data isn't visible without SeeAllData, so recreate what the provisioner resolves.
        insert new ProductRelationshipType(
            Name = 'Bundle to Bundle Component Relationship',
            MainProductRoleCat = 'Bundle',
            AssociatedProductRoleCat = 'BundleComponent'
        );
        insert new Product2(
            Name = 'Service Charge',
            ProductCode = System.Label.RES_Service_Charge_Product_Code,
            IsActive = true,
            ConfigureDuringSale = 'Allowed'
        );
    }

    private static void setUpRecordTypeIds() {
        Map<String, Schema.RecordTypeInfo> infos = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName();
        unitRecordTypeId = infos.get('RES_Residential_Sales').getRecordTypeId();
    }

    // Triggers off for the catalog insert so RES_ProductCatalogTrigger doesn't enqueue the SAP sync.
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

    // ConfigureDuringSale = 'Allowed' is required: a static parent can't take the configurable Service Charge child.
    private static Product2 createUnit(Id catalogId) {
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
        List<Product2> found = [
            SELECT Id FROM Product2 WHERE ProductCode = :System.Label.RES_Service_Charge_Product_Code LIMIT 1
        ];
        return found.isEmpty() ? null : found[0].Id;
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
