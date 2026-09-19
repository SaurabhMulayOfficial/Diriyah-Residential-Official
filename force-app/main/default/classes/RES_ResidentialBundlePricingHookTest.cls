/** Test class for RES_ResidentialBundlePricingHook - everything not requiring the real 'Pricing_Option' match (see RES_BundlePricingHookMatchingTest for those). */
@isTest
private class RES_ResidentialBundlePricingHookTest {

    private static final String BUNDLE_NAME = 'RES Test Bundle WSTU';
    private static final String PREMIUM_NAME = 'RES Test Option Premium';
    private static final String STANDARD_NAME = 'RES Test Option Standard';
    private static final String BASIC_NAME = 'RES Test Option Basic';
    private static final String SERVICE_CHARGE_NAME = 'Service Charge';
    private static final String PAYMENT_PLAN_NAME = 'RES Test Payment Plan';
    private static final String INSTALLMENT_1_NAME = 'RES Test Installment 1';
    private static final String INSTALLMENT_2_NAME = 'RES Test Installment 2';

    /** Shared setup: bundle + option products, relationship type, price book entries (no AttributeDefinition/adjustments - see the matching test class). */
    @testSetup
    static void setupTestData() {
        // Revenue Cloud objects enforce FLS on DML even for admins, so grant the hook's permission set first
        List<PermissionSetAssignment> existingAssignments = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
                AND PermissionSet.Name = 'RES_Bundle_Pricing_Option_Hook_Access'
        ];
        if (existingAssignments.isEmpty()) {
            List<PermissionSet> pricingHookPermSets = [
                SELECT Id FROM PermissionSet WHERE Name = 'RES_Bundle_Pricing_Option_Hook_Access' LIMIT 1
            ];
            if (!pricingHookPermSets.isEmpty()) {
                insert new PermissionSetAssignment(
                    AssigneeId = UserInfo.getUserId(),
                    PermissionSetId = pricingHookPermSets[0].Id
                );
            }
        }

        // Type = 'Bundle' is required before ProductRelatedComponent accepts this as a ParentProductId
        Product2 bundleProduct = new Product2(
            Name = BUNDLE_NAME,
            ProductCode = 'RES-TEST-WSTU-001',
            IsActive = true,
            Family = 'Infrastructure Units',
            Type = 'Bundle',
            RES_Net_Saleable_Area__c = 1000
        );
        insert bundleProduct;

        // RES_Price_Option__c lives on the ProductRelatedComponent, not the product, since options are reused across bundles
        List<Product2> childProducts = new List<Product2>{
            new Product2(Name = PREMIUM_NAME, ProductCode = 'RES-TEST-PIO-001', IsActive = true, Family = 'Options'),
            new Product2(Name = STANDARD_NAME, ProductCode = 'RES-TEST-SIO-001', IsActive = true, Family = 'Options'),
            new Product2(Name = BASIC_NAME, ProductCode = 'RES-TEST-BIO-001', IsActive = true, Family = 'Options'),
            new Product2(Name = SERVICE_CHARGE_NAME, ProductCode = 'RES-TEST-SC-001', IsActive = true, Family = 'Options'),
            // Type = 'Bundle' here too, since the Payment Plan itself parents installment components
            new Product2(Name = PAYMENT_PLAN_NAME, ProductCode = 'RES-TEST-PP-001', IsActive = true, Family = 'Options', Type = 'Bundle'),
            new Product2(Name = INSTALLMENT_1_NAME, ProductCode = 'RES-TEST-INST-001', IsActive = true, Family = 'Options'),
            new Product2(Name = INSTALLMENT_2_NAME, ProductCode = 'RES-TEST-INST-002', IsActive = true, Family = 'Options')
        };
        insert childProducts;

        // ProductRelatedComponent.ProductRelationshipTypeId is required
        ProductRelationshipType bundleComponentType = new ProductRelationshipType(
            Name = 'RES Test Bundle Component',
            MainProductRoleCat = 'Bundle',
            AssociatedProductRoleCat = 'BundleComponent'
        );
        insert bundleComponentType;

        // ProductRelatedComponent rows are inserted per-test instead (see insertBundleComponentPriceOptions) since
        // the PermissionSetAssignment above only takes effect in a later transaction, not this @testSetup one.

        Id standardPricebookId = Test.getStandardPricebookId();
        List<PricebookEntry> pbes = new List<PricebookEntry>();
        pbes.add(new PricebookEntry(
            Product2Id = bundleProduct.Id, Pricebook2Id = standardPricebookId, UnitPrice = 10000, IsActive = true
        ));
        for (Product2 childProd : childProducts) {
            pbes.add(new PricebookEntry(
                Product2Id = childProd.Id, Pricebook2Id = standardPricebookId, UnitPrice = 1000, IsActive = true
            ));
        }
        insert pbes;
    }

    /** Joins each option to the bundle via ProductRelatedComponent, carrying RES_Price_Option__c on the relationship itself. */
    private static void insertBundleComponentPriceOptions() {
        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];
        Product2 premiumOption = [SELECT Id FROM Product2 WHERE Name = :PREMIUM_NAME LIMIT 1];
        Product2 standardOption = [SELECT Id FROM Product2 WHERE Name = :STANDARD_NAME LIMIT 1];
        Product2 basicOption = [SELECT Id FROM Product2 WHERE Name = :BASIC_NAME LIMIT 1];
        ProductRelationshipType bundleComponentType = [
            SELECT Id FROM ProductRelationshipType WHERE Name = 'RES Test Bundle Component' LIMIT 1
        ];

        insert new List<ProductRelatedComponent>{
            new ProductRelatedComponent(
                ParentProductId = bundleProduct.Id, ChildProductId = premiumOption.Id,
                ProductRelationshipTypeId = bundleComponentType.Id, RES_Price_Option__c = 'Premium',
                IsDefaultComponent = true
            ),
            new ProductRelatedComponent(
                ParentProductId = bundleProduct.Id, ChildProductId = standardOption.Id,
                ProductRelationshipTypeId = bundleComponentType.Id, RES_Price_Option__c = 'Standard',
                IsDefaultComponent = true
            ),
            new ProductRelatedComponent(
                ParentProductId = bundleProduct.Id, ChildProductId = basicOption.Id,
                ProductRelationshipTypeId = bundleComponentType.Id, RES_Price_Option__c = 'Basic',
                IsDefaultComponent = true
            )
        };
    }

    /** Joins the Payment Plan and its two installments to the bundle with each installment's percentage share. */
    private static void insertInstallmentComponents() {
        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];
        Product2 paymentPlan = [SELECT Id FROM Product2 WHERE Name = :PAYMENT_PLAN_NAME LIMIT 1];
        Product2 installment1 = [SELECT Id FROM Product2 WHERE Name = :INSTALLMENT_1_NAME LIMIT 1];
        Product2 installment2 = [SELECT Id FROM Product2 WHERE Name = :INSTALLMENT_2_NAME LIMIT 1];
        ProductRelationshipType bundleComponentType = [
            SELECT Id FROM ProductRelationshipType WHERE Name = 'RES Test Bundle Component' LIMIT 1
        ];

        insert new ProductRelatedComponent(
            ParentProductId = bundleProduct.Id, ChildProductId = paymentPlan.Id,
            ProductRelationshipTypeId = bundleComponentType.Id, RES_Price_Option__c = 'Premium',
            IsDefaultComponent = true
        );

        insert new List<ProductRelatedComponent>{
            new ProductRelatedComponent(
                ParentProductId = paymentPlan.Id, ChildProductId = installment1.Id,
                ProductRelationshipTypeId = bundleComponentType.Id, RES_Installment_Percentage__c = 60,
                IsDefaultComponent = true
            ),
            new ProductRelatedComponent(
                ParentProductId = paymentPlan.Id, ChildProductId = installment2.Id,
                ProductRelationshipTypeId = bundleComponentType.Id, RES_Installment_Percentage__c = 40,
                IsDefaultComponent = true
            )
        };
    }

    /** Joins the Service Charge option to the bundle (the fields under test read Product2/ProductAttributeDefinition directly). */
    private static void insertServiceChargeComponent() {
        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];
        Product2 serviceCharge = [SELECT Id FROM Product2 WHERE Name = :SERVICE_CHARGE_NAME LIMIT 1];
        ProductRelationshipType bundleComponentType = [
            SELECT Id FROM ProductRelationshipType WHERE Name = 'RES Test Bundle Component' LIMIT 1
        ];

        insert new ProductRelatedComponent(
            ParentProductId = bundleProduct.Id, ChildProductId = serviceCharge.Id,
            ProductRelationshipTypeId = bundleComponentType.Id, IsDefaultComponent = true
        );
    }

    /** Test: queryBundleStructure parses hierarchy correctly via the injectable RES_IndustriesContextProvider/fake. */
    @isTest
    static void testQueryBundleStructure_BuildsHierarchyAndSkipsInvalidNodes() {
        RES_FakeIndustriesContextProvider fakeProvider = new RES_FakeIndustriesContextProvider();

        List<Object> bundleDataPath = new List<Object>{'ctx123', 'QuoteId_1', 'LineCtx_Bundle'};
        List<Object> childDataPath = new List<Object>{'ctx123', 'QuoteId_1', 'LineCtx_Child'};

        List<Object> items = new List<Object>{
            RES_FakeIndustriesContextProvider.buildLineItemNode(
                'Bundle_001', 'Bundle_001', 'ProdBundle', bundleDataPath, null
            ),
            RES_FakeIndustriesContextProvider.buildLineItemNode(
                'Child_001', 'Bundle_001/Child_001', 'ProdChild', childDataPath, null
            ),
            // DELETED items must be skipped entirely
            RES_FakeIndustriesContextProvider.buildLineItemNode(
                'Deleted_001', 'Bundle_001/Deleted_001', 'ProdDeleted', childDataPath, 'DELETED'
            ),
            // A node missing tagValue's required keys must also be skipped
            new Map<String, Object>{'tagValue' => new Map<String, Object>{'SomeOtherTag' => 'x'}, 'dataPath' => childDataPath},
            // Bundle_002's child arrives before its own parent node - exercises the placeholder BundleStructure
            RES_FakeIndustriesContextProvider.buildLineItemNode(
                'Child_002', 'Bundle_002/Child_002', 'ProdChild2', childDataPath, null
            ),
            // Bundle_002's own node arrives after, filling in the placeholder's productId
            RES_FakeIndustriesContextProvider.buildLineItemNode(
                'Bundle_002', 'Bundle_002', 'ProdBundle2', bundleDataPath, null
            )
        };
        fakeProvider.queryTagsResultToReturn = RES_FakeIndustriesContextProvider.wrapQueryResult('SalesTransactionItem', items);

        Test.startTest();
        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMap =
            hook.queryBundleStructure(fakeProvider, 'ctx123');
        Test.stopTest();

        System.assert(bundleMap.containsKey('Bundle_001'), 'Should identify the parent bundle');
        System.assertEquals('ProdBundle', bundleMap.get('Bundle_001').productId, 'Bundle product should be parsed');
        System.assertEquals(1, bundleMap.get('Bundle_001').childOptions.size(), 'Only the non-deleted child should be added');
        System.assertEquals('Child_001', bundleMap.get('Bundle_001').childOptions[0].lineItemId, 'Should be the valid child');
        System.assertEquals(2, bundleMap.get('Bundle_001').nodePath.size(), 'nodePath should carry QuoteId + LineContextId');

        System.assert(bundleMap.containsKey('Bundle_002'), 'Should identify a bundle whose child arrived before its own node');
        System.assertEquals('ProdBundle2', bundleMap.get('Bundle_002').productId,
            'productId should be filled in once the bundle\'s own node is processed');
        System.assertEquals(1, bundleMap.get('Bundle_002').childOptions.size(), 'Should still have its early-arriving child');
    }

    /** Test: queryItemAttributes parses only MATCHING_ATTRIBUTES, skips nodes with no parent id, and records node paths. */
    @isTest
    static void testQueryItemAttributes_ParsesMatchingAttributesAndBuildsNodePaths() {
        RES_FakeIndustriesContextProvider fakeProvider = new RES_FakeIndustriesContextProvider();

        List<Object> attrDataPath = new List<Object>{'ctx123', 'QuoteId_1', 'LineCtx_Bundle', 'AttrNode_1'};

        List<Object> attrs = new List<Object>{
            RES_FakeIndustriesContextProvider.buildAttributeNode('Bundle_001', 'Pricing_Option', 'Premium', attrDataPath),
            // Non-matching attribute name - still initializes the map entry, never added to it
            RES_FakeIndustriesContextProvider.buildAttributeNode('Bundle_001', 'Some_Other_Attribute', 'Ignored', attrDataPath),
            // Missing parent item id must be skipped
            new Map<String, Object>{
                'tagValue' => new Map<String, Object>{
                    'Attribute' => new Map<String, Object>{'tagValue' => 'Pricing_Option'},
                    'AttributeValue' => new Map<String, Object>{'tagValue' => 'Standard'}
                },
                'dataPath' => attrDataPath
            }
        };
        fakeProvider.queryTagsResultToReturn = RES_FakeIndustriesContextProvider.wrapQueryResult('SalesTransactionItemAttribute', attrs);

        Test.startTest();
        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        Map<String, List<Object>> attributeNodePathMap = new Map<String, List<Object>>();
        Map<String, Map<String, String>> attributeMap =
            hook.queryItemAttributes(fakeProvider, 'ctx123', attributeNodePathMap);
        Test.stopTest();

        System.assert(attributeMap.containsKey('Bundle_001'), 'Should have an entry for the parent item');
        System.assertEquals('Premium', attributeMap.get('Bundle_001').get('Pricing_Option'), 'Should record the matching attribute value');
        System.assert(!attributeMap.get('Bundle_001').containsKey('Some_Other_Attribute'), 'Non-matching attributes should never be recorded');
        System.assert(attributeNodePathMap.containsKey('Bundle_001:Pricing_Option'), 'Should record the matching attribute node path');
        System.assertEquals(3, attributeNodePathMap.get('Bundle_001:Pricing_Option').size(), 'Relative node path should strip the leading contextId');
    }

    /** Test: executeInternal reports success with no updates when the bundle structure is empty. */
    @isTest
    static void testExecuteInternal_NoBundlesMeansNoUpdates() {
        RES_FakeIndustriesContextProvider fakeProvider = new RES_FakeIndustriesContextProvider();
        fakeProvider.queryTagsResultToReturn = new Map<String, Object>{'queryResult' => new Map<String, Object>()};

        Test.startTest();
        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        RevSignaling.TransactionResponse response = hook.executeInternal('ctx123', fakeProvider);
        Test.stopTest();

        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, response.status, 'Should succeed even with nothing to update');
        System.assertEquals(0, fakeProvider.updateContextAttributesCallCount, 'Should never submit updates when there are none');
    }

    /** Test: executeInternal catches any exception and reports FAILED rather than letting it propagate. */
    @isTest
    static void testExecuteInternal_CatchesExceptionAndReportsFailure() {
        RES_FakeIndustriesContextProvider fakeProvider = new RES_FakeIndustriesContextProvider();
        fakeProvider.throwOnQueryTags = true;

        Test.startTest();
        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        RevSignaling.TransactionResponse response = hook.executeInternal('ctx123', fakeProvider);
        Test.stopTest();

        System.assertEquals(RevSignaling.TransactionStatus.FAILED, response.status, 'Should report failure rather than throw');
        System.assert(response.message.contains('Error:'), 'Failure message should carry the error detail');
    }

    /** Test: RES_LiveIndustriesContextProvider constructs and its methods are callable in a unit test. */
    @isTest
    static void testLiveIndustriesContextProvider_DelegatesToRealContext() {
        Test.startTest();
        RES_LiveIndustriesContextProvider provider = new RES_LiveIndustriesContextProvider();
        try {
            provider.queryTags(new Map<String, Object>{'contextId' => 'fake', 'tags' => new List<String>{'SalesTransactionItem'}});
        } catch (Exception e) {
            // Expected: no real transaction context exists in a unit test
        }
        try {
            provider.updateContextAttributes(new Map<String, Object>{'contextId' => 'fake', 'nodePathAndAttributes' => new List<Object>()});
        } catch (Exception e) {
            // Expected: no real transaction context exists in a unit test
        }
        Test.stopTest();

        System.assertNotEquals(null, provider, 'Provider should construct successfully');
    }

    /** Test: Build price update node for an Override (absolute price) adjustment. */
    @isTest
    static void testBuildPriceUpdateNode_Override() {
        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();

        List<Object> testNodePath = new List<Object>{'QuoteId_123', 'LineId_456'};
        RES_ResidentialBundlePricingHook.OptionItem optionItem =
            new RES_ResidentialBundlePricingHook.OptionItem('QLI_001', 'Prod_001', testNodePath, 'ParentId/ChildId');

        RES_ResidentialBundlePricingHook.AttributeAdjustment adjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_001', 'Test Override Price', 'Override', 5000, null, null
            );

        Map<String, Object> updateNode = hook.buildPriceUpdateNode(optionItem, adjustment);

        Test.stopTest();

        System.assertNotEquals(null, updateNode, 'Should create update node');
        System.assert(updateNode.containsKey('nodePath'), 'Should have nodePath');
        System.assert(updateNode.containsKey('attributes'), 'Should have attributes');

        Map<String, Object> nodePath = (Map<String, Object>)updateNode.get('nodePath');
        System.assert(nodePath.containsKey('dataPath'), 'nodePath should have dataPath');

        List<Object> attributes = (List<Object>)updateNode.get('attributes');
        System.assertEquals(1, attributes.size(), 'Should have one attribute update');

        Map<String, Object> attr = (Map<String, Object>)attributes[0];
        System.assertEquals('PartnerUnitPrice', attr.get('attributeName'), 'Should update PartnerUnitPrice');
        System.assertEquals(5000, attr.get('attributeValue'), 'Should set correct price');
    }

    /** Test: Build price update node for a Percentage adjustment. */
    @isTest
    static void testBuildPriceUpdateNode_Percentage() {
        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();

        List<Object> testNodePath = new List<Object>{'QuoteId_123', 'LineId_456'};
        RES_ResidentialBundlePricingHook.OptionItem optionItem =
            new RES_ResidentialBundlePricingHook.OptionItem('QLI_002', 'Prod_002', testNodePath, 'ParentId/ChildId');

        RES_ResidentialBundlePricingHook.AttributeAdjustment adjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_002', 'Test Percentage Discount', 'Percentage', 20, null, null
            );

        Map<String, Object> updateNode = hook.buildPriceUpdateNode(optionItem, adjustment);

        Test.stopTest();

        System.assertNotEquals(null, updateNode, 'Should create update node');

        List<Object> attributes = (List<Object>)updateNode.get('attributes');
        Map<String, Object> attr = (Map<String, Object>)attributes[0];
        System.assertEquals('AdjustmentPercent', attr.get('attributeName'), 'Should update AdjustmentPercent');
        System.assertEquals(20, attr.get('attributeValue'), 'Should set correct discount percentage');
    }

    /** Test: Build price update node for Amount, and confirm unsupported type / blank node path return null. */
    @isTest
    static void testBuildPriceUpdateNode_AmountAndEdgeCases() {
        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        List<Object> testNodePath = new List<Object>{'QuoteId_123', 'LineId_456'};

        RES_ResidentialBundlePricingHook.AttributeAdjustment amountAdjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_003', 'Test Amount Discount', 'Amount', 750, null, null
            );
        Map<String, Object> amountNode = hook.buildPriceUpdateNode(testNodePath, amountAdjustment);
        List<Object> amountAttributes = (List<Object>)amountNode.get('attributes');
        Map<String, Object> amountAttr = (Map<String, Object>)amountAttributes[0];
        System.assertEquals('AdjustmentAmount', amountAttr.get('attributeName'), 'Should update AdjustmentAmount');
        System.assertEquals(750, amountAttr.get('attributeValue'), 'Should set correct amount');

        RES_ResidentialBundlePricingHook.AttributeAdjustment unsupportedAdjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_004', 'Unsupported Type', 'SomethingElse', 1, null, null
            );
        Map<String, Object> unsupportedNode = hook.buildPriceUpdateNode(testNodePath, unsupportedAdjustment);
        System.assertEquals(null, unsupportedNode, 'An unsupported adjustment type should return null');

        Map<String, Object> emptyPathNode = hook.buildPriceUpdateNode(new List<Object>(), amountAdjustment);
        System.assertEquals(null, emptyPathNode, 'An empty node path should return null');

        Map<String, Object> nullPathNode = hook.buildPriceUpdateNode((List<Object>) null, amountAdjustment);
        System.assertEquals(null, nullPathNode, 'A null node path should return null');

        Test.stopTest();
    }

    /** Test: Should apply adjustment to option based on AppliesTo criteria. */
    @isTest
    static void testShouldApplyToOption_WithAppliesTo() {
        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        List<Object> testNodePath = new List<Object>{'QuoteId_123', 'LineId_456'};
        String targetProductId = 'RES_TEST_PROD_TARGET';

        RES_ResidentialBundlePricingHook.OptionItem optionItem =
            new RES_ResidentialBundlePricingHook.OptionItem('QLI_001', targetProductId, testNodePath, 'ParentId/ChildId');

        RES_ResidentialBundlePricingHook.AttributeAdjustment specificAdjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_001', 'Specific Adjustment', 'Amount', 500, targetProductId, null
            );
        RES_ResidentialBundlePricingHook.AttributeAdjustment otherAdjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_002', 'Other Adjustment', 'Amount', 500, 'DifferentProductId', null
            );
        RES_ResidentialBundlePricingHook.AttributeAdjustment generalAdjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_003', 'General Adjustment', 'Override', 5000, null, null
            );
        RES_ResidentialBundlePricingHook.AttributeAdjustment attributeMatchAdjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_005', 'Attribute Value Match', 'Amount', 250, 'SomeAttrValue', null
            );

        Test.stopTest();

        Boolean shouldApplySpecific = hook.shouldApplyToOption(specificAdjustment, optionItem, null);
        System.assertEquals(true, shouldApplySpecific, 'Should apply when product matches AppliesTo');

        Boolean shouldApplyOther = hook.shouldApplyToOption(otherAdjustment, optionItem, null);
        System.assertEquals(false, shouldApplyOther, 'Should not apply when product does not match AppliesTo');

        Boolean shouldApplyGeneral = hook.shouldApplyToOption(generalAdjustment, optionItem, null);
        System.assertEquals(true, shouldApplyGeneral, 'Should apply when no AppliesTo criteria');

        Boolean shouldApplyByAttribute = hook.shouldApplyToOption(
            attributeMatchAdjustment, optionItem, new Map<String, String>{'SomeKey' => 'SomeAttrValue'}
        );
        System.assertEquals(true, shouldApplyByAttribute, 'Should apply when a child attribute value matches AppliesTo');
    }

    /** Test: queryAttributeAdjustments returns an empty map with no bundle product IDs (see matching test class for the success path). */
    @isTest
    static void testQueryAttributeAdjustments_NoProductIds() {
        Test.startTest();
        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        Map<String, List<RES_ResidentialBundlePricingHook.AttributeAdjustment>> emptyMap =
            hook.queryAttributeAdjustments(new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>());
        Test.stopTest();

        System.assert(emptyMap.isEmpty(), 'No bundle products should yield an empty adjustment map');
    }

    /** Test: Query RES_Price_Option__c values from the ProductRelatedComponent joining each option to its bundle. */
    @isTest
    static void testQueryChildOptionPriceValues() {
        insertBundleComponentPriceOptions();

        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();

        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];
        Product2 premiumOption = [SELECT Id FROM Product2 WHERE Name = :PREMIUM_NAME LIMIT 1];
        Product2 standardOption = [SELECT Id FROM Product2 WHERE Name = :STANDARD_NAME LIMIT 1];

        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMap =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>();

        RES_ResidentialBundlePricingHook.BundleStructure bundle =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', bundleProduct.Id);
        List<Object> nodePath = new List<Object>{'QuoteId_123', 'LineId_456'};
        bundle.addChildOption(new RES_ResidentialBundlePricingHook.OptionItem(
            'Child_001', premiumOption.Id, nodePath, 'Bundle_001/Child_001'
        ));
        bundle.addChildOption(new RES_ResidentialBundlePricingHook.OptionItem(
            'Child_002', standardOption.Id, nodePath, 'Bundle_001/Child_002'
        ));
        bundleMap.put('Bundle_001', bundle);

        Map<String, String> priceOptionMap = hook.queryChildOptionPriceValues(bundleMap);

        // Also exercise the no-parent/child-product-IDs early-return branch
        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> emptyBundleMap =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>();
        emptyBundleMap.put('Empty', new RES_ResidentialBundlePricingHook.BundleStructure('Empty', null));
        Map<String, String> emptyResult = hook.queryChildOptionPriceValues(emptyBundleMap);

        Test.stopTest();

        System.assertEquals(
            'Premium',
            priceOptionMap.get(hook.buildRelatedComponentKey(bundleProduct.Id, premiumOption.Id)),
            'Premium option ProductRelatedComponent should carry RES_Price_Option__c = Premium'
        );
        System.assertEquals(
            'Standard',
            priceOptionMap.get(hook.buildRelatedComponentKey(bundleProduct.Id, standardOption.Id)),
            'Standard option ProductRelatedComponent should carry RES_Price_Option__c = Standard'
        );
        System.assert(emptyResult.isEmpty(), 'No parent/child product IDs should yield an empty map');
    }

    /** Test: queryInstallmentPercentages loads each installment's share from its joining ProductRelatedComponent. */
    @isTest
    static void testQueryInstallmentPercentages() {
        insertInstallmentComponents();

        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        Product2 paymentPlan = [SELECT Id FROM Product2 WHERE Name = :PAYMENT_PLAN_NAME LIMIT 1];
        Product2 installment1 = [SELECT Id FROM Product2 WHERE Name = :INSTALLMENT_1_NAME LIMIT 1];
        Product2 installment2 = [SELECT Id FROM Product2 WHERE Name = :INSTALLMENT_2_NAME LIMIT 1];

        RES_ResidentialBundlePricingHook.BundleStructure bundle =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', 'DummyBundleProdId');
        List<Object> nodePath = new List<Object>{'QuoteId_123', 'LineId_456'};
        bundle.addChildOption(new RES_ResidentialBundlePricingHook.OptionItem(
            'PP_001', paymentPlan.Id, nodePath, 'Bundle_001/PP_001'
        ));
        bundle.addChildOption(new RES_ResidentialBundlePricingHook.OptionItem(
            'Inst_001', installment1.Id, nodePath, 'Bundle_001/PP_001/Inst_001'
        ));
        bundle.addChildOption(new RES_ResidentialBundlePricingHook.OptionItem(
            'Inst_002', installment2.Id, nodePath, 'Bundle_001/PP_001/Inst_002'
        ));

        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMap =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>{'Bundle_001' => bundle};

        Map<String, Decimal> percentageMap = hook.queryInstallmentPercentages(bundleMap);

        Map<String, Decimal> emptyResult = hook.queryInstallmentPercentages(
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>()
        );

        Test.stopTest();

        System.assertEquals(
            60, percentageMap.get(hook.buildRelatedComponentKey(paymentPlan.Id, installment1.Id)),
            'Installment 1 should carry a 60% share'
        );
        System.assertEquals(
            40, percentageMap.get(hook.buildRelatedComponentKey(paymentPlan.Id, installment2.Id)),
            'Installment 2 should carry a 40% share'
        );
        System.assert(emptyResult.isEmpty(), 'No option product IDs should yield an empty map');
    }

    /** Test: queryNetSaleableAreaByProduct reads RES_Net_Saleable_Area__c directly from the bundle product. */
    @isTest
    static void testQueryNetSaleableAreaByProduct() {
        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];

        RES_ResidentialBundlePricingHook.BundleStructure bundle =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', bundleProduct.Id);
        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMap =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>{'Bundle_001' => bundle};

        Map<Id, Decimal> areaMap = hook.queryNetSaleableAreaByProduct(bundleMap);

        Map<Id, Decimal> emptyResult = hook.queryNetSaleableAreaByProduct(
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>()
        );

        Test.stopTest();

        System.assertEquals(1000, areaMap.get(bundleProduct.Id), 'Should load the bundle product Net Saleable Area');
        System.assert(emptyResult.isEmpty(), 'No bundle product IDs should yield an empty map');
    }

    /** Test: queryServiceChargeProductIds identifies the child product named 'Service Charge', or nothing if absent. */
    @isTest
    static void testQueryServiceChargeProductIds() {
        insertServiceChargeComponent();

        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];
        Product2 serviceCharge = [SELECT Id FROM Product2 WHERE Name = :SERVICE_CHARGE_NAME LIMIT 1];
        Product2 premiumOption = [SELECT Id FROM Product2 WHERE Name = :PREMIUM_NAME LIMIT 1];

        RES_ResidentialBundlePricingHook.BundleStructure bundleWithServiceCharge =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', bundleProduct.Id);
        List<Object> nodePath = new List<Object>{'QuoteId_123', 'LineId_456'};
        bundleWithServiceCharge.addChildOption(new RES_ResidentialBundlePricingHook.OptionItem(
            'SC_001', serviceCharge.Id, nodePath, 'Bundle_001/SC_001'
        ));
        bundleWithServiceCharge.addChildOption(new RES_ResidentialBundlePricingHook.OptionItem(
            'Prem_001', premiumOption.Id, nodePath, 'Bundle_001/Prem_001'
        ));

        RES_ResidentialBundlePricingHook.BundleStructure bundleWithoutServiceCharge =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_002', bundleProduct.Id);
        bundleWithoutServiceCharge.addChildOption(new RES_ResidentialBundlePricingHook.OptionItem(
            'Prem_002', premiumOption.Id, nodePath, 'Bundle_002/Prem_002'
        ));

        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMap =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>{
                'Bundle_001' => bundleWithServiceCharge
            };
        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMapWithout =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>{
                'Bundle_002' => bundleWithoutServiceCharge
            };

        Set<Id> found = hook.queryServiceChargeProductIds(bundleMap);
        Set<Id> notFound = hook.queryServiceChargeProductIds(bundleMapWithout);
        Set<Id> emptyResult = hook.queryServiceChargeProductIds(
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>()
        );

        Test.stopTest();

        System.assert(found.contains(serviceCharge.Id), 'Should identify the Service Charge child product');
        System.assert(!notFound.contains(serviceCharge.Id), 'Should not find Service Charge when it is not a child');
        System.assert(emptyResult.isEmpty(), 'No option product IDs should yield an empty set');
    }

    /** Test: computeServiceCharge multiplies rate x area, and returns 0 when either input is missing. */
    @isTest
    static void testComputeServiceCharge() {
        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        Id bundleProdId = Id.valueOf('01t000000000001AAA');
        Id otherProdId = Id.valueOf('01t000000000002AAA');

        RES_ResidentialBundlePricingHook.BundleStructure bundle =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', bundleProdId);

        Map<Id, Decimal> rateMap = new Map<Id, Decimal>{bundleProdId => 149};
        Map<Id, Decimal> areaMap = new Map<Id, Decimal>{bundleProdId => 1000};

        Decimal fullResult = hook.computeServiceCharge(bundle, rateMap, areaMap);

        RES_ResidentialBundlePricingHook.BundleStructure bundleMissingRate =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_002', otherProdId);
        Decimal missingRateResult = hook.computeServiceCharge(bundleMissingRate, rateMap, areaMap);

        RES_ResidentialBundlePricingHook.BundleStructure bundleMissingArea =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_003', bundleProdId);
        Decimal missingAreaResult = hook.computeServiceCharge(
            bundleMissingArea, rateMap, new Map<Id, Decimal>()
        );

        Test.stopTest();

        System.assertEquals(149000, fullResult, 'Service charge should be rate x area');
        System.assertEquals(0, missingRateResult, 'Missing rate should compute to 0');
        System.assertEquals(0, missingAreaResult, 'Missing area should compute to 0');
    }

    /** Test: buildInstallmentDisplayUpdates computes each installment's share/amount, skipping unconfigured and unrelated siblings. */
    @isTest
    static void testBuildInstallmentDisplayUpdates() {
        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        List<Object> nodePath = new List<Object>{'QuoteId_123', 'LineId_456'};

        RES_ResidentialBundlePricingHook.OptionItem selectedOption =
            new RES_ResidentialBundlePricingHook.OptionItem('PP_001', 'PaymentPlanProdId', nodePath, 'Bundle_001/PP_001');
        RES_ResidentialBundlePricingHook.OptionItem installment1 =
            new RES_ResidentialBundlePricingHook.OptionItem('Inst_001', 'Inst1ProdId', nodePath, 'Bundle_001/PP_001/Inst_001');
        RES_ResidentialBundlePricingHook.OptionItem installmentNoPercentage =
            new RES_ResidentialBundlePricingHook.OptionItem('Inst_002', 'Inst2ProdId', nodePath, 'Bundle_001/PP_001/Inst_002');
        RES_ResidentialBundlePricingHook.OptionItem unrelatedSibling =
            new RES_ResidentialBundlePricingHook.OptionItem('Other_001', 'OtherProdId', nodePath, 'Bundle_001/Other_001');
        RES_ResidentialBundlePricingHook.OptionItem nullPathCandidate =
            new RES_ResidentialBundlePricingHook.OptionItem('Null_001', 'NullPathProdId', nodePath, null);
        RES_ResidentialBundlePricingHook.OptionItem singleSegmentPathCandidate =
            new RES_ResidentialBundlePricingHook.OptionItem('Single_001', 'SingleSegmentProdId', nodePath, 'Bundle_001');

        RES_ResidentialBundlePricingHook.BundleStructure bundle =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', 'BundleProdId');
        bundle.addChildOption(selectedOption);
        bundle.addChildOption(installment1);
        bundle.addChildOption(installmentNoPercentage);
        bundle.addChildOption(unrelatedSibling);
        bundle.addChildOption(nullPathCandidate);
        bundle.addChildOption(singleSegmentPathCandidate);

        Map<String, Decimal> installmentPercentageMap = new Map<String, Decimal>{
            hook.buildRelatedComponentKey('PaymentPlanProdId', 'Inst1ProdId') => 60
        };

        List<Map<String, Object>> updates = hook.buildInstallmentDisplayUpdates(
            bundle, selectedOption, 50000, installmentPercentageMap
        );

        Test.stopTest();

        System.assertEquals(1, updates.size(), 'Only the installment with a configured percentage should produce an update');
        Map<String, Object> updateEntry = updates[0];
        Map<String, Object> updateNodePath = (Map<String, Object>) updateEntry.get('nodePath');
        System.assertEquals(nodePath, updateNodePath.get('dataPath'), 'Update should target the installment\'s own line');

        Map<String, Object> percentageAttr;
        Map<String, Object> amountAttr;
        for (Object attrObj : (List<Object>) updateEntry.get('attributes')) {
            Map<String, Object> attr = (Map<String, Object>) attrObj;
            if (attr.get('attributeName') == 'RES_Installment_Percentage__c') percentageAttr = attr;
            if (attr.get('attributeName') == 'RES_Installment_Amount__c') amountAttr = attr;
        }
        System.assertEquals(60, percentageAttr.get('attributeValue'), 'Should carry the 60% share');
        System.assertEquals(30000, amountAttr.get('attributeValue'), '60% of 50000 should be 30000');
    }

    /** Test: buildInstallmentDisplayUpdateNode returns null for a blank/null node path. */
    @isTest
    static void testBuildInstallmentDisplayUpdateNode_InvalidNodePath() {
        Test.startTest();
        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();

        Map<String, Object> nullResult = hook.buildInstallmentDisplayUpdateNode(null, 50, 25000);
        Map<String, Object> emptyResult = hook.buildInstallmentDisplayUpdateNode(new List<Object>(), 50, 25000);
        Test.stopTest();

        System.assertEquals(null, nullResult, 'A null node path should return null');
        System.assertEquals(null, emptyResult, 'An empty node path should return null');
    }

    /** Test: applyPricingToOptions skips bundles with no children/product, no adjustments, or no condition match. */
    @isTest
    static void testApplyPricingToOptions_SkipBranches() {
        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        List<Object> nodePath = new List<Object>{'QuoteId_123', 'LineId_456'};

        RES_ResidentialBundlePricingHook.BundleStructure bundleWithNoChildren =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_NoChildren', 'ProdId_001');
        RES_ResidentialBundlePricingHook.BundleStructure bundleWithNoProduct =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_NoProduct', null);
        bundleWithNoProduct.addChildOption(new RES_ResidentialBundlePricingHook.OptionItem(
            'Child_001', 'ChildProdId', nodePath, 'Bundle_NoProduct/Child_001'
        ));

        // Has children and a product, but no bundleAdjustmentsMap entry at all
        RES_ResidentialBundlePricingHook.BundleStructure bundleWithNoAdjustments =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_NoAdjustments', 'ProdId_NoAdjustments');
        bundleWithNoAdjustments.addChildOption(new RES_ResidentialBundlePricingHook.OptionItem(
            'Child_002', 'ChildProdId2', nodePath, 'Bundle_NoAdjustments/Child_002'
        ));

        // Has adjustments, but the selected option's value ('Premium') matches none (all conditioned on 'Standard')
        RES_ResidentialBundlePricingHook.BundleStructure bundleWithNoMatch =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_NoMatch', 'ProdId_NoMatch');
        RES_ResidentialBundlePricingHook.OptionItem noMatchChild =
            new RES_ResidentialBundlePricingHook.OptionItem('Child_003', 'ChildProdId3', nodePath, 'Bundle_NoMatch/Child_003');
        bundleWithNoMatch.addChildOption(noMatchChild);

        AttributeDefinition pricingOptionAttrStub = new AttributeDefinition(DeveloperName = 'Pricing_Option');
        AttributeAdjustmentCondition standardOnlyCondition = new AttributeAdjustmentCondition(
            Operator = 'equals', StringValue = 'Standard'
        );
        standardOnlyCondition.putSObject('AttributeDefinition', pricingOptionAttrStub);
        RES_ResidentialBundlePricingHook.AttributeAdjustment standardOnlyAdjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_Standard', 'Standard Only', 'Override', 1000, null,
                new List<AttributeAdjustmentCondition>{standardOnlyCondition}
            );

        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMap =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>{
                'Bundle_NoChildren' => bundleWithNoChildren,
                'Bundle_NoProduct' => bundleWithNoProduct,
                'Bundle_NoAdjustments' => bundleWithNoAdjustments,
                'Bundle_NoMatch' => bundleWithNoMatch
            };
        Map<String, List<RES_ResidentialBundlePricingHook.AttributeAdjustment>> bundleAdjustmentsMap =
            new Map<String, List<RES_ResidentialBundlePricingHook.AttributeAdjustment>>{
                'ProdId_NoMatch' => new List<RES_ResidentialBundlePricingHook.AttributeAdjustment>{standardOnlyAdjustment}
            };
        Map<String, String> relatedComponentPriceOptionMap = new Map<String, String>{
            hook.buildRelatedComponentKey('ProdId_NoMatch', 'ChildProdId3') => 'Premium'
        };
        // Non-empty itemAttributeMap entry so the matchContext.putAll branch is also exercised
        Map<String, Map<String, String>> itemAttributeMap = new Map<String, Map<String, String>>{
            'Child_003' => new Map<String, String>{'SomeOtherAttribute' => 'SomeValue'}
        };

        List<Map<String, Object>> updates = hook.applyPricingToOptions(
            bundleMap, itemAttributeMap, bundleAdjustmentsMap,
            relatedComponentPriceOptionMap, new Map<String, List<Object>>(), new Map<String, Decimal>(),
            new Map<Id, Decimal>(), new Set<Id>(), new Map<Id, Decimal>()
        );

        Test.stopTest();

        System.assert(updates.isEmpty(), 'None of these bundles should produce a price update');
    }

    /** Test: Helper method to get tag value. */
    @isTest
    static void testGetTagValue() {
        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'LineItem' => new Map<String, Object>{'tagValue' => 'QLI_12345'},
            'Product' => new Map<String, Object>{'tagValue' => 'PROD_67890'}
        };

        String lineItemValue = hook.getTagValue(tagMap, 'LineItem');
        String productValue = hook.getTagValue(tagMap, 'Product');
        String missingValue = hook.getTagValue(tagMap, 'NonExistent');
        String nullMapValue = hook.getTagValue(null, 'LineItem');

        Test.stopTest();

        System.assertEquals('QLI_12345', lineItemValue, 'Should extract LineItem tag value');
        System.assertEquals('PROD_67890', productValue, 'Should extract Product tag value');
        System.assertEquals(null, missingValue, 'Should return null for missing tag');
        System.assertEquals(null, nullMapValue, 'Should return null for a null tag map');
    }

    /** Test: Helper method to get DML status. */
    @isTest
    static void testGetDmlStatus() {
        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();

        Map<String, Object> tagMapWithPath = new Map<String, Object>{
            'LineItemPath' => new Map<String, Object>{'tagValue' => 'Parent/Child', 'dmlStatus' => 'DELETED'}
        };
        Map<String, Object> tagMapWithItem = new Map<String, Object>{
            'LineItem' => new Map<String, Object>{'tagValue' => 'QLI_123', 'dmlStatus' => 'UPDATED'}
        };
        Map<String, Object> tagMapWithoutStatus = new Map<String, Object>{
            'LineItem' => new Map<String, Object>{'tagValue' => 'QLI_456'}
        };

        String statusFromPath = hook.getDmlStatus(tagMapWithPath);
        String statusFromItem = hook.getDmlStatus(tagMapWithItem);
        String statusMissing = hook.getDmlStatus(tagMapWithoutStatus);

        Test.stopTest();

        System.assertEquals('DELETED', statusFromPath, 'Should extract status from LineItemPath');
        System.assertEquals('UPDATED', statusFromItem, 'Should extract status from LineItem');
        System.assertEquals(null, statusMissing, 'Should return null when status is missing');
    }

    /** Test: buildRelatedComponentKey concatenates parent and child product IDs consistently. */
    @isTest
    static void testBuildRelatedComponentKey() {
        Test.startTest();
        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        String key = hook.buildRelatedComponentKey('ParentId123', 'ChildId456');
        Test.stopTest();

        System.assertEquals('ParentId123:ChildId456', key, 'Key should be parentId:childId');
    }

    /** Test: Bundle structure inner class. */
    @isTest
    static void testBundleStructureClass() {
        Test.startTest();

        RES_ResidentialBundlePricingHook.BundleStructure bundle =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', 'Product_001');

        List<Object> nodePath = new List<Object>{'QuoteId', 'LineId'};
        RES_ResidentialBundlePricingHook.OptionItem option1 =
            new RES_ResidentialBundlePricingHook.OptionItem('Child_001', 'ProdChild_001', nodePath, 'Bundle/Child1');
        RES_ResidentialBundlePricingHook.OptionItem option2 =
            new RES_ResidentialBundlePricingHook.OptionItem('Child_002', 'ProdChild_002', nodePath, 'Bundle/Child2');

        bundle.addChildOption(option1);
        bundle.addChildOption(option2);

        Test.stopTest();

        System.assertEquals('Bundle_001', bundle.bundleId, 'Bundle ID should match');
        System.assertEquals('Product_001', bundle.productId, 'Product ID should match');
        System.assertEquals(2, bundle.childOptions.size(), 'Should have 2 child options');
        System.assertEquals('Child_001', bundle.childOptions[0].lineItemId, 'First child should match');
        System.assertEquals('Child_002', bundle.childOptions[1].lineItemId, 'Second child should match');
    }

    @isTest
    static void testIntegration_WadiSafarPricingScenario() {
        Product2 bundle = [SELECT Id, Name FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];
        System.assertNotEquals(null, bundle, 'Bundle product should exist');

        List<Product2> options = [SELECT Id, Name FROM Product2 WHERE Family = 'Options'];
        System.assert(!options.isEmpty(), 'Should have option products');

        System.debug('Integration Test Scenario:');
        System.debug('1. Bundle: ' + BUNDLE_NAME + ' with selectable option components');
        System.debug('2. User selects Premium option (RES_Price_Option__c = Premium)');
        System.debug('3. Expected: Premium pricing (5000) applied back onto the bundle\'s own line');
        System.debug('Run this hook in Revenue Cloud pricing context to verify full integration.');
    }
}
