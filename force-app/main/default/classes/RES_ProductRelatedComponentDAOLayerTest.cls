@IsTest
private class RES_ProductRelatedComponentDAOLayerTest {

    @TestSetup
    static void setup() {
        // RES_ProductTrigger enqueues an SAP sync callout, which isn't under test here
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        config.RES_Triggers_Off__c = true;
        upsert config;

        Map<String, Schema.RecordTypeInfo> recordTypes = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName();
        Product2 paymentPlan = RES_TestDataFactory.createPaymentPlan('DAO Test Plan', recordTypes.get(System.Label.RES_Product_Payment_Plan_RT).getRecordTypeId());
        // Factory reuses the same unique External ID for plan and installment
        update new Product2(Id = paymentPlan.Id, RES_Product_External_ID__c = 'DAO-TEST-PP');
        Product2 installment = RES_TestDataFactory.createInstallment('DAO Test Installment', recordTypes.get(System.Label.RES_Product_Installment_RT).getRecordTypeId());
        update new Product2(Id = installment.Id, RES_Condition_Type__c = 'Y002', RES_Condition_Months__c = 2, RES_Condition_Days__c = 60);
        Product2 unit = new Product2(Name = 'DAO Test Unit', IsActive = true, Type = 'Bundle', RES_CIP_Type__c = 'Unit',
            RecordTypeId = recordTypes.get('RES_Residential_Sales').getRecordTypeId());
        insert unit;

        ProductRelatedComponent planToInstallment = RES_TestDataFactory.createPRC(paymentPlan, installment);
        insert new ProductRelatedComponent(
            ParentProductId = unit.Id,
            ChildProductId = paymentPlan.Id,
            ProductRelationshipTypeId = planToInstallment.ProductRelationshipTypeId,
            Quantity = 1,
            QuoteVisibility = 'Always',
            IsDefaultComponent = true
        );
    }

    private static Product2 productByName(String name) {
        return [SELECT Id FROM Product2 WHERE Name = :name LIMIT 1];
    }

    @IsTest
    static void testGetComponentsByParentProducts_ReturnsInstallmentConditionFields() {
        Id planId = productByName('DAO Test Plan').Id;

        Test.startTest();
        List<ProductRelatedComponent> components = new RES_ProductRelatedComponentDAOLayer().getComponentsByParentProducts(new Set<Id>{ planId });
        Test.stopTest();

        System.assertEquals(1, components.size());
        System.assertEquals('Y002', components[0].ChildProduct.RES_Condition_Type__c);
        System.assertEquals(2, components[0].ChildProduct.RES_Condition_Months__c);
        System.assertEquals(60, components[0].ChildProduct.RES_Condition_Days__c);
    }

    @IsTest
    static void testGetPaymentPlanAssignments_ReturnsUnitToPlanLink() {
        Id planId = productByName('DAO Test Plan').Id;

        Test.startTest();
        List<ProductRelatedComponent> assignments = new RES_ProductRelatedComponentDAOLayer().getPaymentPlanAssignments(new Set<Id>{ planId });
        Test.stopTest();

        System.assertEquals(1, assignments.size());
        System.assertEquals(productByName('DAO Test Unit').Id, assignments[0].ParentProductId);
    }

    @IsTest
    static void testGetComponentsByChildProductsAndParentAndChild_ReturnLinks() {
        Id planId = productByName('DAO Test Plan').Id;
        Id unitId = productByName('DAO Test Unit').Id;
        RES_ProductRelatedComponentDAOLayer dao = new RES_ProductRelatedComponentDAOLayer();

        Test.startTest();
        List<ProductRelatedComponent> byChild = dao.getComponentsByChildProducts(new Set<Id>{ planId });
        List<ProductRelatedComponent> byParentAndChild = dao.getComponentsByParentProductsAndChild(new Set<Id>{ unitId }, planId);
        Test.stopTest();

        System.assertEquals(1, byChild.size());
        System.assertEquals(1, byParentAndChild.size());
    }

    @IsTest
    static void testEmptyInputs_ReturnEmptyLists() {
        RES_ProductRelatedComponentDAOLayer dao = new RES_ProductRelatedComponentDAOLayer();

        System.assert(dao.getComponentsByParentProducts(null).isEmpty());
        System.assert(dao.getPaymentPlanAssignments(new Set<Id>()).isEmpty());
        System.assert(dao.getComponentsByChildProducts(null).isEmpty());
        System.assert(dao.getComponentsByParentProductsAndChild(new Set<Id>(), null).isEmpty());
    }

    // Puts the setup Unit->Plan component into a "Payment Plan" group and returns the Unit Id.
    private static Id putSetupComponentInPaymentPlanGroup() {
        Id unitId = productByName('DAO Test Unit').Id;
        ProductComponentGroup componentGroup = new ProductComponentGroup(
            ParentProductId = unitId, Name = 'Payment Plan', Code = unitId + '-PP',
            Sequence = 10, MinBundleComponents = 1, MaxBundleComponents = 1
        );
        insert componentGroup;
        ProductRelatedComponent component = [SELECT Id FROM ProductRelatedComponent WHERE ParentProductId = :unitId LIMIT 1];
        update new ProductRelatedComponent(Id = component.Id, ProductComponentGroupId = componentGroup.Id);
        return unitId;
    }

    @IsTest
    static void testGetGroupComponentsByUnits_ReturnsPlanActiveFlagAndValidityEnd() {
        Id unitId = putSetupComponentInPaymentPlanGroup();
        Product2 plan = productByName('DAO Test Plan');
        Date validityEnd = Date.today().addDays(-3);
        update new Product2(Id = plan.Id, RES_Validity_End_Date__c = validityEnd);
        RES_ProductRelatedComponentDAOLayer dao = new RES_ProductRelatedComponentDAOLayer();

        Test.startTest();
        List<ProductRelatedComponent> inGroup = dao.getGroupComponentsByUnits(new Set<Id>{ unitId }, 'Payment Plan');
        List<ProductRelatedComponent> otherGroup = dao.getGroupComponentsByUnits(new Set<Id>{ unitId }, 'Some Other Group');
        Test.stopTest();

        System.assertEquals(1, inGroup.size());
        System.assertEquals(true, inGroup[0].IsDefaultComponent);
        System.assertEquals(validityEnd, inGroup[0].ChildProduct.RES_Validity_End_Date__c);
        System.assertEquals([SELECT IsActive FROM Product2 WHERE Id = :plan.Id].IsActive, inGroup[0].ChildProduct.IsActive);
        System.assertEquals(0, otherGroup.size(), 'Only the named group is returned');
    }

    @IsTest
    static void testGetGroupComponentsByUnits_InvalidInputsReturnEmptyList() {
        RES_ProductRelatedComponentDAOLayer dao = new RES_ProductRelatedComponentDAOLayer();
        Set<Id> someUnit = new Set<Id>{ productByName('DAO Test Unit').Id };

        System.assert(dao.getGroupComponentsByUnits(null, 'Payment Plan').isEmpty());
        System.assert(dao.getGroupComponentsByUnits(new Set<Id>(), 'Payment Plan').isEmpty());
        System.assert(dao.getGroupComponentsByUnits(someUnit, null).isEmpty());
        System.assert(dao.getGroupComponentsByUnits(someUnit, '').isEmpty());
    }

    @IsTest
    static void testGetExpiredPaymentPlanComponentsLocator_ReturnsOnlyExpiredPlans() {
        Id unitId = putSetupComponentInPaymentPlanGroup();
        Id planId = productByName('DAO Test Plan').Id;
        RES_ProductRelatedComponentDAOLayer dao = new RES_ProductRelatedComponentDAOLayer();

        update new Product2(Id = planId, RES_Validity_End_Date__c = Date.today().addDays(-1));
        List<ProductRelatedComponent> expired = new List<ProductRelatedComponent>();
        Database.QueryLocatorIterator expiredIterator = dao.getExpiredPaymentPlanComponentsLocator(Date.today(), 'Payment Plan').iterator();
        while (expiredIterator.hasNext()) {
            expired.add((ProductRelatedComponent) expiredIterator.next());
        }
        System.assertEquals(1, expired.size(), 'Plan ended yesterday is expired');
        System.assertEquals(unitId, expired[0].ParentProductId);

        update new Product2(Id = planId, RES_Validity_End_Date__c = Date.today());
        Database.QueryLocatorIterator todayIterator = dao.getExpiredPaymentPlanComponentsLocator(Date.today(), 'Payment Plan').iterator();
        System.assertEquals(false, todayIterator.hasNext(), 'Plan ending today is not expired yet');

        update new Product2(Id = planId, RES_Validity_End_Date__c = null);
        Database.QueryLocatorIterator noEndIterator = dao.getExpiredPaymentPlanComponentsLocator(Date.today(), 'Payment Plan').iterator();
        System.assertEquals(false, noEndIterator.hasNext(), 'A plan with no end date never expires');
    }
}
