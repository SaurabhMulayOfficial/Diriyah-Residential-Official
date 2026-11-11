@IsTest
private class RES_CatalogPaymentPlansControllerTest {

    @TestSetup
    static void setup() {
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        config.RES_Triggers_Off__c = true;
        upsert config;
    }

    private static Id recordTypeId(String developerName) {
        return Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName().get(developerName).getRecordTypeId();
    }

    @IsTest
    static void groupsVersionsUnderRootLatestFirst() {
        ProductCatalog catalog = new ProductCatalog(Name = 'Test Catalog');
        insert catalog;
        Id planRt = recordTypeId('RES_Residential_Payment_Plan');

        Product2 root = new Product2(Name = 'Plan A', RecordTypeId = planRt, Type = 'Bundle', RES_Business_Entity__c = catalog.Id, IsActive = false);
        Product2 standalone = new Product2(Name = 'Plan B', RecordTypeId = planRt, Type = 'Bundle', RES_Business_Entity__c = catalog.Id, IsActive = true);
        insert new List<Product2>{ root, standalone };
        Product2 v1 = new Product2(Name = 'Plan A POC 40', RecordTypeId = planRt, Type = 'Bundle', RES_Business_Entity__c = catalog.Id,
            RES_Parent_Payment_Plan__c = root.Id, RES_Version__c = 1, IsActive = false);
        Product2 v2 = new Product2(Name = 'Plan A POC 60', RecordTypeId = planRt, Type = 'Bundle', RES_Business_Entity__c = catalog.Id,
            RES_Parent_Payment_Plan__c = root.Id, RES_Version__c = 2, IsActive = true);
        insert new List<Product2>{ v1, v2 };

        ProductRelationshipType relType = new ProductRelationshipType(Name = 'Bundle to Bundle Component Relationship',
            MainProductRoleCat = 'Bundle', AssociatedProductRoleCat = 'BundleComponent');
        insert relType;
        ProductComponentGroup grp = new ProductComponentGroup(Name = 'Installments', ParentProductId = v2.Id, Sequence = 10);
        insert grp;
        Product2 installment = new Product2(Name = 'Down Payment', RecordTypeId = recordTypeId('RES_Residential_Installment'),
            RES_CIP_Type__c = 'Installment', IsActive = true);
        insert installment;
        insert new ProductRelatedComponent(ParentProductId = v2.Id, ChildProductId = installment.Id, ProductComponentGroupId = grp.Id,
            ProductRelationshipTypeId = relType.Id, Quantity = 1, Sequence = 10, IsDefaultComponent = true, IsComponentRequired = true);

        Test.startTest();
        List<RES_CatalogPaymentPlansController.PlanFamily> families = RES_CatalogPaymentPlansController.getPaymentPlans(catalog.Id);
        Test.stopTest();

        System.assertEquals(2, families.size(), 'One family per root plan');
        RES_CatalogPaymentPlansController.PlanFamily familyA;
        for (RES_CatalogPaymentPlansController.PlanFamily family : families) {
            if (family.rootId == root.Id) {
                familyA = family;
            }
        }
        System.assertNotEquals(null, familyA);
        System.assertEquals(3, familyA.versions.size());
        System.assertEquals(v2.Id, familyA.versions[0].id, 'Latest version first');
        System.assertEquals(true, familyA.versions[0].isActive);
        System.assertEquals(1, familyA.versions[0].installmentCount);
        System.assertEquals(v1.Id, familyA.versions[1].id);
        System.assertEquals(root.Id, familyA.versions[2].id, 'Original plan last');
        System.assertEquals(null, familyA.versions[2].version);
    }

    @IsTest
    static void returnsEmptyForNullCatalog() {
        System.assertEquals(0, RES_CatalogPaymentPlansController.getPaymentPlans(null).size());
    }
}
