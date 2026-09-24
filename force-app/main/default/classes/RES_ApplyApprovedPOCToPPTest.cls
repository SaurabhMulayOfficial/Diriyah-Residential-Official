@IsTest
private class RES_ApplyApprovedPOCToPPTest {

    private static Id unitRecordTypeId;
    private static Id paymentPlanRecordTypeId;
    private static Id installmentRecordTypeId;

    @TestSetup
    static void setup() {
        insert new ProductSellingModel(Name = 'One-Time', SellingModelType = 'OneTime', Status = 'Active');
        insert new ProductRelationshipType(
            Name = 'Bundle to Bundle Component Relationship',
            MainProductRoleCat = 'Bundle',
            AssociatedProductRoleCat = 'BundleComponent'
        );
        insert new Pricebook2(Name = 'Residential Sales', IsActive = true);
    }

    private static void setUpRecordTypeIds() {
        Map<String, Schema.RecordTypeInfo> infos = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName();
        unitRecordTypeId = infos.get('RES_Residential_Sales').getRecordTypeId();
        paymentPlanRecordTypeId = infos.get('RES_Residential_Payment_Plan').getRecordTypeId();
        installmentRecordTypeId = infos.get('RES_Residential_Installment').getRecordTypeId();
    }

    /*
     * ProductCatalog insert fires RES_ProductCatalogTrigger, and Product2 inserts fire
     * RES_ProductTrigger - both of which (when triggers are enabled) can enqueue the SAP
     * integration queueable, which throws a NullPointerException from RES_SAPTokenProvider.getToken()
     * in this environment (no Named Credential configured for tests) as soon as Test.stopTest()
     * forces it to run synchronously. Unrelated to this class - triggers are left off for the rest
     * of the test method (every Product2 this test inserts, plus whatever the invocable itself
     * inserts), not just this one insert, since the same queueable can be enqueued by either
     * object's trigger. Safe to never restore: the whole transaction, including this Custom
     * Setting change, is rolled back automatically when the test method ends.
     */
    private static ProductCatalog createCatalog() {
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        config.RES_Triggers_Off__c = true;
        upsert config;

        ProductCatalog catalog = new ProductCatalog(Name = 'Test Catalog');
        insert catalog;
        return catalog;
    }

    private static Id relationshipTypeId() {
        return [SELECT Id FROM ProductRelationshipType WHERE Name = 'Bundle to Bundle Component Relationship' LIMIT 1].Id;
    }

    private static Id sellingModelId() {
        return [SELECT Id FROM ProductSellingModel WHERE Name = 'One-Time' LIMIT 1].Id;
    }

    private static Id residentialSalesPricebookId() {
        return [SELECT Id FROM Pricebook2 WHERE Name = 'Residential Sales' LIMIT 1].Id;
    }

    /*
     * Both books are needed just to satisfy the org's own validation (a custom price cannot be
     * created before a standard one exists for the same product), matching
     * RES_PaymentPlanConfiguratorServiceTest's setup. Cloning PricebookEntry rows onto a NEW
     * product, however, is not verifiable end-to-end from this test: Apex test context hides the
     * Standard Price Book's own Pricebook2 row from relationship traversal (confirmed against
     * this org - "Pricebook2.IsStandard = true" never matches inside a test method unless
     * @IsTest(SeeAllData=true) is used), so RES_PricebookEntryDAOLayer.getPricebookEntryRelatedToProducts(..., true)
     * finds nothing to clone for the new product, which in turn means the follow-up
     * isStandard=false clone fails the same "standard price must exist first" validation for
     * that new product - silently, since that insert runs with allOrNone=false. See the assertions
     * below: only ProductSellingModelOption (which has no such dependency) is checked on cloned records.
     */
    private static void addPricingAndSellingModel(Id productId) {
        insert new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = productId, UnitPrice = 0, IsActive = true);
        insert new PricebookEntry(Pricebook2Id = residentialSalesPricebookId(), Product2Id = productId, UnitPrice = 0, IsActive = true, UseStandardPrice = false);
        insert new ProductSellingModelOption(Product2Id = productId, ProductSellingModelId = sellingModelId(), IsDefault = true);
    }

    /**
     * Builds one root Payment Plan (RES_Price_Option__c = 'Option 1') with 3 Installments
     * (POC%/Installment% of 20/50/30, summing to 100) linked via ProductRelatedComponent under
     * an "Installments" ProductComponentGroup - mirroring exactly what
     * RES_PaymentPlanConfiguratorService builds for a brand-new Payment Plan. Also wires one
     * Unit to this Payment Plan via ProductRelatedComponent, mirroring
     * RES_PaymentPlanBundleProvisioner's initial provisioning.
     */
    private static Map<String, Id> buildRootPlanWithInstallments(Id catalogId) {
        Product2 unit = new Product2(
            Name = 'Test Unit',
            IsActive = true,
            RecordTypeId = unitRecordTypeId,
            RES_Business_Entity__c = catalogId,
            Type = 'Bundle'
        );
        insert unit;

        Product2 plan = new Product2(
            Name = 'Test Payment Plan',
            IsActive = true,
            RecordTypeId = paymentPlanRecordTypeId,
            Type = 'Bundle',
            RES_Catalog__c = catalogId,
            RES_Business_Entity__c = catalogId,
            RES_Price_Option__c = 'Option 1'
        );
        insert plan;
        addPricingAndSellingModel(plan.Id);

        ProductComponentGroup planGroup = new ProductComponentGroup(
            Name = 'Test Payment Plan Installments',
            ParentProductId = plan.Id,
            Sequence = 10,
            MinBundleComponents = 4,
            MaxBundleComponents = 4
        );
        insert planGroup;

        /*
         * RES_POC_Percentage__c is a cumulative completion MILESTONE (confirmed against real org
         * data: a live plan has installments at 20/40/70/100, not incremental shares summing to
         * 100) - the value at which that installment falls due. RES_Installment_Percentage__c is
         * the separate, actual incremental payment share, and is what sums to 100.
         */
        List<Product2> installments = new List<Product2>{
            new Product2(Name = 'Downpayment', IsActive = true, RecordTypeId = installmentRecordTypeId, RES_Sequence__c = 1, RES_POC_Percentage__c = 20, RES_Installment_Percentage__c = 20),
            new Product2(Name = 'Installment 1', IsActive = true, RecordTypeId = installmentRecordTypeId, RES_Sequence__c = 2, RES_POC_Percentage__c = 40, RES_Installment_Percentage__c = 20),
            new Product2(Name = 'Installment 2', IsActive = true, RecordTypeId = installmentRecordTypeId, RES_Sequence__c = 3, RES_POC_Percentage__c = 70, RES_Installment_Percentage__c = 30),
            new Product2(Name = 'Final Payment', IsActive = true, RecordTypeId = installmentRecordTypeId, RES_Sequence__c = 4, RES_POC_Percentage__c = 100, RES_Installment_Percentage__c = 30)
        };
        insert installments;
        for (Product2 installment : installments) {
            addPricingAndSellingModel(installment.Id);
        }

        List<ProductRelatedComponent> planComponents = new List<ProductRelatedComponent>();
        for (Integer i = 0; i < installments.size(); i++) {
            planComponents.add(new ProductRelatedComponent(
                ParentProductId = plan.Id,
                ChildProductId = installments[i].Id,
                ProductComponentGroupId = planGroup.Id,
                ProductRelationshipTypeId = relationshipTypeId(),
                Quantity = 1,
                IsComponentRequired = true,
                IsDefaultComponent = true,
                IsQuantityEditable = false,
                DoesBundlePriceIncludeChild = true,
                QuoteVisibility = 'Always',
                Sequence = (i + 1) * 10,
                RES_Installment_Percentage__c = installments[i].RES_Installment_Percentage__c
            ));
        }
        insert planComponents;

        ProductComponentGroup unitGroup = new ProductComponentGroup(
            Name = 'Payment Plan',
            ParentProductId = unit.Id,
            Code = unit.Id + '-PP',
            Sequence = 10,
            MinBundleComponents = 1,
            MaxBundleComponents = 1
        );
        insert unitGroup;

        ProductRelatedComponent unitComponent = new ProductRelatedComponent(
            ParentProductId = unit.Id,
            ChildProductId = plan.Id,
            ProductComponentGroupId = unitGroup.Id,
            ProductRelationshipTypeId = relationshipTypeId(),
            Quantity = 1,
            IsComponentRequired = false,
            IsDefaultComponent = true,
            IsQuantityEditable = false,
            DoesBundlePriceIncludeChild = false,
            QuoteVisibility = 'Always',
            RES_Price_Option__c = 'Option 1'
        );
        insert unitComponent;

        return new Map<String, Id>{
            'unit' => unit.Id,
            'plan' => plan.Id,
            'unitComponent' => unitComponent.Id,
            'downpayment' => installments[0].Id,
            'installment1' => installments[1].Id,
            'installment2' => installments[2].Id,
            'finalPayment' => installments[3].Id
        };
    }

    private static RES_Project_Completion_Report__c createApprovedPOC(Id catalogId, Decimal approvedPOC) {
        return new RES_Project_Completion_Report__c(
            RES_Project__c = catalogId,
            RES_POC__c = approvedPOC
        );
    }

    /**
     * approvedPOC=55 against installments whose own milestones are 20/40/70/100 (matching a real
     * live plan's shape) means Downpayment (milestone 20) and Installment 1 (milestone 40) have
     * both already come due (each milestone < 55) and merge into one installment carrying their
     * combined 40% share; Installment 2 (milestone 70) and Final Payment (milestone 100) haven't
     * come due yet and are cloned 1:1. This is also a regression test for a real bug: an earlier
     * version of this class summed the (already-cumulative) milestones instead of comparing each
     * one directly to the approved POC%, which merged only the first installment instead of both.
     */
    @IsTest
    static void mergesInstallmentsBelowApprovedPOCAndClonesTheRest() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Map<String, Id> ids = buildRootPlanWithInstallments(catalog.Id);

        RES_ApplyApprovedPOCToFuturePaymentPlan.Input input = new RES_ApplyApprovedPOCToFuturePaymentPlan.Input();
        input.pocRecord = createApprovedPOC(catalog.Id, 55);

        Test.startTest();
        RES_ApplyApprovedPOCToFuturePaymentPlan.applyApprovedPOCToFuturePaymentPlan(
            new List<RES_ApplyApprovedPOCToFuturePaymentPlan.Input>{ input }
        );
        Test.stopTest();

        List<Product2> newVersions = [
            SELECT Id, RES_Version__c, RES_Price_Option__c, RES_Catalog__c
            FROM Product2
            WHERE RES_Parent_Payment_Plan__c = :ids.get('plan')
        ];
        System.assertEquals(1, newVersions.size(), 'Expected exactly one new Payment Plan version');
        Product2 newVersion = newVersions[0];
        System.assertEquals(1, newVersion.RES_Version__c);
        System.assertEquals('Option 1', newVersion.RES_Price_Option__c, 'Price Option must carry over to the new version');

        List<ProductComponentGroup> newGroups = [
            SELECT Id, Name, MinBundleComponents, MaxBundleComponents
            FROM ProductComponentGroup
            WHERE ParentProductId = :newVersion.Id
        ];
        System.assertEquals(1, newGroups.size(), 'Expected one Installments group on the new version');
        System.assertEquals('Test Payment Plan Installments', newGroups[0].Name, 'New group should mirror the root plan group Name');
        System.assertEquals(3, newGroups[0].MinBundleComponents);
        System.assertEquals(3, newGroups[0].MaxBundleComponents);

        List<ProductRelatedComponent> newPlanComponents = [
            SELECT Id, ChildProductId, RES_Installment_Percentage__c, Sequence, ProductComponentGroupId, ProductRelationshipTypeId
            FROM ProductRelatedComponent
            WHERE ParentProductId = :newVersion.Id
            ORDER BY Sequence ASC
        ];
        System.assertEquals(3, newPlanComponents.size(), 'Expected the merged installment (Downpayment+Installment 1) plus the two untouched installments, linked via PRC');
        System.assertEquals(40, newPlanComponents[0].RES_Installment_Percentage__c, 'Merged installment should carry the combined 20+20 share');
        System.assertEquals(30, newPlanComponents[1].RES_Installment_Percentage__c, 'Installment 2 should be untouched');
        System.assertEquals(30, newPlanComponents[2].RES_Installment_Percentage__c, 'Final Payment should be untouched');
        for (ProductRelatedComponent prc : newPlanComponents) {
            System.assertEquals(newGroups[0].Id, prc.ProductComponentGroupId);
            System.assertNotEquals(null, prc.ProductRelationshipTypeId);
        }

        Set<Id> newInstallmentIds = new Set<Id>();
        for (ProductRelatedComponent prc : newPlanComponents) {
            newInstallmentIds.add(prc.ChildProductId);
        }
        List<Product2> newInstallments = [SELECT Id, RES_POC_Percentage__c FROM Product2 WHERE Id IN :newInstallmentIds];
        System.assertEquals(3, newInstallments.size());

        // Every new installment must have its ProductSellingModelOption cloned across (see addPricingAndSellingModel for why PricebookEntry cloning isn't asserted here)
        System.assertEquals(3, [SELECT COUNT() FROM ProductSellingModelOption WHERE Product2Id IN :newInstallmentIds]);

        // The new Payment Plan version itself must also have its selling-model row cloned
        System.assertEquals(1, [SELECT COUNT() FROM ProductSellingModelOption WHERE Product2Id = :newVersion.Id]);

        /*
         * The Unit's existing component must now point at the new version, keeping its Price
         * Option. Queried by ParentProductId (the Unit), not the original component's Id -
         * relinkUnitsToNewVersion replaces the row (insert new, delete old) rather than updating
         * ChildProductId in place, so the original ids.get('unitComponent') record no longer exists.
         */
        ProductRelatedComponent unitComponent = [
            SELECT Id, ChildProductId, RES_Price_Option__c
            FROM ProductRelatedComponent
            WHERE ParentProductId = :ids.get('unit')
        ];
        System.assertEquals(newVersion.Id, unitComponent.ChildProductId, 'Unit must be repointed at the new Payment Plan version');
        System.assertEquals('Option 1', unitComponent.RES_Price_Option__c, 'Repointing must not disturb the existing Price Option value');

        // The root plan's own PRC/group configuration must be untouched
        System.assertEquals(4, [SELECT COUNT() FROM ProductRelatedComponent WHERE ParentProductId = :ids.get('plan')]);
    }

    @IsTest
    static void doesNothingWhenPocRecordHasNoProject() {
        RES_ApplyApprovedPOCToFuturePaymentPlan.Input input = new RES_ApplyApprovedPOCToFuturePaymentPlan.Input();
        input.pocRecord = new RES_Project_Completion_Report__c(RES_POC__c = 50);

        Test.startTest();
        RES_ApplyApprovedPOCToFuturePaymentPlan.applyApprovedPOCToFuturePaymentPlan(
            new List<RES_ApplyApprovedPOCToFuturePaymentPlan.Input>{ input }
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Product2 WHERE RES_Version__c != null]);
    }

    @IsTest
    static void handlesEmptyInputListGracefully() {
        Test.startTest();
        RES_ApplyApprovedPOCToFuturePaymentPlan.applyApprovedPOCToFuturePaymentPlan(new List<RES_ApplyApprovedPOCToFuturePaymentPlan.Input>());
        Test.stopTest();
    }

    /**
     * Every version clones from the ROOT plan (RES_Parent_Payment_Plan__c always points at the
     * root, not the previous version - versions fan out flatly rather than chaining). After the
     * first approval, the Unit's ProductRelatedComponent is repointed at v1 (not the root). A
     * second approval must still find and repoint that same Unit component to v2, even though it
     * no longer references the root or anything in parentToClonedProductsMap's keys directly.
     */
    @IsTest
    static void secondApprovalRepointsUnitFromPriorVersionToNewVersion() {
        setUpRecordTypeIds();
        ProductCatalog catalog = createCatalog();
        Map<String, Id> ids = buildRootPlanWithInstallments(catalog.Id);

        RES_ApplyApprovedPOCToFuturePaymentPlan.Input firstInput = new RES_ApplyApprovedPOCToFuturePaymentPlan.Input();
        firstInput.pocRecord = createApprovedPOC(catalog.Id, 75);
        RES_ApplyApprovedPOCToFuturePaymentPlan.applyApprovedPOCToFuturePaymentPlan(
            new List<RES_ApplyApprovedPOCToFuturePaymentPlan.Input>{ firstInput }
        );

        List<Product2> allChildrenAfterFirst = [SELECT Id, RES_Version__c FROM Product2 WHERE RES_Parent_Payment_Plan__c = :ids.get('plan')];
        System.assertEquals(1, allChildrenAfterFirst.size(), 'Expected exactly one version after the first approval');
        Product2 firstVersion = allChildrenAfterFirst[0];

        // Queried by ParentProductId (the Unit) - relinkUnitsToNewVersion replaces the row, so the original ids.get('unitComponent') Id no longer exists
        ProductRelatedComponent afterFirstApproval = [SELECT ChildProductId FROM ProductRelatedComponent WHERE ParentProductId = :ids.get('unit')];
        System.assertEquals(firstVersion.Id, afterFirstApproval.ChildProductId, 'Sanity check: Unit should be on v1 after the first approval');

        RES_ApplyApprovedPOCToFuturePaymentPlan.Input secondInput = new RES_ApplyApprovedPOCToFuturePaymentPlan.Input();
        secondInput.pocRecord = createApprovedPOC(catalog.Id, 100);

        Test.startTest();
        RES_ApplyApprovedPOCToFuturePaymentPlan.applyApprovedPOCToFuturePaymentPlan(
            new List<RES_ApplyApprovedPOCToFuturePaymentPlan.Input>{ secondInput }
        );
        Test.stopTest();

        List<Product2> allVersions = [
            SELECT Id, RES_Version__c
            FROM Product2
            WHERE RES_Parent_Payment_Plan__c = :ids.get('plan')
            ORDER BY RES_Version__c ASC
        ];
        System.assertEquals(2, allVersions.size(), 'Root should now have two versions as direct children (versions fan out flatly from the root)');
        System.assertEquals(1, allVersions[0].RES_Version__c);
        System.assertEquals(2, allVersions[1].RES_Version__c);

        ProductRelatedComponent unitComponent = [SELECT ChildProductId FROM ProductRelatedComponent WHERE ParentProductId = :ids.get('unit')];
        System.assertEquals(allVersions[1].Id, unitComponent.ChildProductId,
            'Unit was pointing at v1 (not the root) before this approval - relinking must still find and repoint it to v2');
    }
}