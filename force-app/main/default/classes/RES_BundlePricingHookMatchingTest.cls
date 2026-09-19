/** Tests for RES_ResidentialBundlePricingHook needing the real 'Pricing_Option' AttributeDefinition match (SeeAllData=true, so no @testSetup). */
@isTest(SeeAllData=true)
private class RES_BundlePricingHookMatchingTest {

    private static final String BUNDLE_NAME = 'RES Test Matching Bundle WSTU';
    private static final String PREMIUM_NAME = 'RES Test Matching Option Premium';
    // Must be the literal 'Service Charge' - queryServiceChargeProductIds matches on this exact Product2.Name
    private static final String SERVICE_CHARGE_NAME = 'Service Charge';
    private static final String RELATIONSHIP_TYPE_NAME = 'RES Test Matching Bundle Component';

    /** Creates the bundle + Premium option, relationship type, and price book entries (not @testSetup - called per test). */
    private static void setupCoreData() {
        Product2 bundleProduct = new Product2(
            Name = BUNDLE_NAME,
            ProductCode = 'RES-TEST-MATCH-WSTU-001',
            IsActive = true,
            Family = 'Infrastructure Units',
            Type = 'Bundle',
            UsageModelType = 'Pack',
            RES_Net_Saleable_Area__c = 1000
        );
        insert bundleProduct;

        List<Product2> childProducts = new List<Product2>{
            new Product2(Name = PREMIUM_NAME, ProductCode = 'RES-TEST-MATCH-PIO-001', IsActive = true, Family = 'Options'),
            new Product2(Name = SERVICE_CHARGE_NAME, ProductCode = 'RES-TEST-MATCH-SC-001', IsActive = true, Family = 'Options')
        };
        insert childProducts;

        // MainProductRoleCat + AssociatedProductRoleCat is org-wide unique - reuse the real pair instead of duplicating
        List<ProductRelationshipType> existingTypes = [
            SELECT Id FROM ProductRelationshipType
            WHERE MainProductRoleCat = 'Bundle' AND AssociatedProductRoleCat = 'BundleComponent'
            LIMIT 1
        ];
        if (existingTypes.isEmpty()) {
            insert new ProductRelationshipType(
                Name = RELATIONSHIP_TYPE_NAME,
                MainProductRoleCat = 'Bundle',
                AssociatedProductRoleCat = 'BundleComponent'
            );
        }

        // Required on each ProductRelatedComponent under a Type='Bundle' parent
        insert new ProductComponentGroup(Name = 'RES Test Matching Options Group', ParentProductId = bundleProduct.Id);

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

    /** Joins the Premium option to the bundle via ProductRelatedComponent, carrying RES_Price_Option__c. */
    private static void insertBundleComponentPriceOption() {
        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];
        Product2 premiumOption = [SELECT Id FROM Product2 WHERE Name = :PREMIUM_NAME LIMIT 1];
        ProductRelationshipType bundleComponentType = [
            SELECT Id FROM ProductRelationshipType
            WHERE MainProductRoleCat = 'Bundle' AND AssociatedProductRoleCat = 'BundleComponent'
            LIMIT 1
        ];
        ProductComponentGroup componentGroup = [
            SELECT Id FROM ProductComponentGroup
            WHERE ParentProductId = :bundleProduct.Id AND Name = 'RES Test Matching Options Group'
            LIMIT 1
        ];

        insert new ProductRelatedComponent(
            ParentProductId = bundleProduct.Id, ChildProductId = premiumOption.Id,
            ProductRelationshipTypeId = bundleComponentType.Id, RES_Price_Option__c = 'Premium',
            IsDefaultComponent = true, ProductComponentGroupId = componentGroup.Id
        );
    }

    /** Sets SC_RATE (DefaultValue on a ProductAttributeDefinition scoped to the bundle) - read via SOQL by the hook. */
    private static void insertServiceChargeRateAttribute() {
        Product2 bundleProduct = [SELECT Id, BasedOnId FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];

        List<AttributeDefinition> existingScRateAttrs = [
            SELECT Id FROM AttributeDefinition WHERE DeveloperName = 'SC_RATE' LIMIT 1
        ];
        AttributeDefinition scRateAttr;
        if (!existingScRateAttrs.isEmpty()) {
            scRateAttr = existingScRateAttrs[0];
        } else {
            scRateAttr = new AttributeDefinition(
                Name = 'RES Test Matching Service Charge Rate', Label = 'RES Test Matching Service Charge Rate',
                DeveloperName = 'SC_RATE', DataType = 'Number', IsActive = true
            );
            insert scRateAttr;
        }

        // Reuse the bundle's existing classification if it already has one, rather than creating a conflicting second one
        Id classificationId = bundleProduct.BasedOnId;
        if (classificationId == null) {
            ProductClassification scClassification = new ProductClassification(
                Code = 'RES_TEST_MATCH_SC_CLASS_' + String.valueOf(Crypto.getRandomInteger()).right(8),
                Name = 'RES Test Matching Service Charge Classification',
                Status = 'Active'
            );
            insert scClassification;
            classificationId = scClassification.Id;
            update new Product2(Id = bundleProduct.Id, BasedOnId = classificationId);
        }

        ProductClassificationAttr scClassificationAttr = new ProductClassificationAttr(
            Name = 'RES Test Matching Service Charge Rate',
            ProductClassificationId = classificationId,
            AttributeDefinitionId = scRateAttr.Id
        );
        insert scClassificationAttr;

        insert new ProductAttributeDefinition(
            Name = 'RES Test Matching Service Charge Rate',
            Product2Id = bundleProduct.Id,
            AttributeDefinitionId = scRateAttr.Id,
            ProductClassificationAttributeId = scClassificationAttr.Id,
            DefaultValue = '149',
            IsReadOnly = true
        );
    }

    /** Creates the PriceAdjustmentSchedule/Rule/Condition/Adjustment chain, reusing the org's real 'Pricing_Option' attribute. */
    private static void insertPricingRulesAndAdjustments() {
        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];

        PriceAdjustmentSchedule pas = new PriceAdjustmentSchedule(
            Name = 'RES Test Matching Pricing Options',
            ScheduleType = 'Attribute',
            AdjustmentMethod = 'Range',
            IsActive = true,
            EffectiveFrom = DateTime.now()
        );
        insert pas;

        List<AttributeDefinition> existingPricingOptionAttrs = [
            SELECT Id FROM AttributeDefinition WHERE DeveloperName = 'Pricing_Option' LIMIT 1
        ];
        AttributeDefinition pricingOptionAttr;
        if (!existingPricingOptionAttrs.isEmpty()) {
            pricingOptionAttr = existingPricingOptionAttrs[0];
        } else {
            pricingOptionAttr = new AttributeDefinition(
                Name = 'RES Test Matching Pricing Option', Label = 'RES Test Matching Pricing Option',
                DeveloperName = 'Pricing_Option', DataType = 'Text', IsActive = true
            );
            insert pricingOptionAttr;
        }

        ProductClassification bundleClassification = new ProductClassification(
            Code = 'RES_TEST_MATCH_CLASS_' + String.valueOf(Crypto.getRandomInteger()).right(8),
            Name = 'RES Test Matching Classification',
            Status = 'Active'
        );
        insert bundleClassification;

        insert new ProductClassificationAttr(
            Name = 'RES Test Matching Pricing Option',
            ProductClassificationId = bundleClassification.Id,
            AttributeDefinitionId = pricingOptionAttr.Id,
            IsPriceImpacting = true
        );

        // Product2.Type is createable but not updateable - update via a minimal sObject
        update new Product2(Id = bundleProduct.Id, BasedOnId = bundleClassification.Id);

        List<AttributeBasedAdjRule> rules = new List<AttributeBasedAdjRule>{
            new AttributeBasedAdjRule(Name = 'RES Test Matching Premium Rule'),
            new AttributeBasedAdjRule(Name = 'RES Test Matching Standard Rule'),
            new AttributeBasedAdjRule(Name = 'RES Test Matching Basic Rule')
        };
        insert rules;

        insert new List<AttributeAdjustmentCondition>{
            new AttributeAdjustmentCondition(
                AttributeBasedAdjRuleId = rules[0].Id, AttributeDefinitionId = pricingOptionAttr.Id,
                ProductId = bundleProduct.Id, Operator = 'equals', StringValue = 'Premium'
            ),
            new AttributeAdjustmentCondition(
                AttributeBasedAdjRuleId = rules[1].Id, AttributeDefinitionId = pricingOptionAttr.Id,
                ProductId = bundleProduct.Id, Operator = 'equals', StringValue = 'Standard'
            ),
            new AttributeAdjustmentCondition(
                AttributeBasedAdjRuleId = rules[2].Id, AttributeDefinitionId = pricingOptionAttr.Id,
                ProductId = bundleProduct.Id, Operator = 'equals', StringValue = 'Basic'
            )
        };

        insert new List<AttributeBasedAdjustment>{
            new AttributeBasedAdjustment(
                PriceAdjustmentScheduleId = pas.Id, ProductId = bundleProduct.Id,
                AttributeBasedAdjRuleId = rules[0].Id, AdjustmentType = 'Override',
                AdjustmentValue = 5000, EffectiveFrom = DateTime.now()
            ),
            new AttributeBasedAdjustment(
                PriceAdjustmentScheduleId = pas.Id, ProductId = bundleProduct.Id,
                AttributeBasedAdjRuleId = rules[1].Id, AdjustmentType = 'Override',
                AdjustmentValue = 3000, EffectiveFrom = DateTime.now()
            ),
            new AttributeBasedAdjustment(
                PriceAdjustmentScheduleId = pas.Id, ProductId = bundleProduct.Id,
                AttributeBasedAdjRuleId = rules[2].Id, AdjustmentType = 'Percentage',
                AdjustmentValue = 20, EffectiveFrom = DateTime.now()
            )
        };
    }

    /** Test: Find matching adjustments for a selected option with RES_Price_Option__c = Premium. */
    @isTest
    static void testFindMatchingAdjustments_Premium() {
        setupCoreData();
        insertPricingRulesAndAdjustments();

        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];

        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMap =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>();
        bundleMap.put('Bundle_001', new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', bundleProduct.Id));

        List<RES_ResidentialBundlePricingHook.AttributeAdjustment> adjList =
            hook.queryAttributeAdjustments(bundleMap).get(bundleProduct.Id);

        Map<String, String> matchContext = new Map<String, String>{
            'Pricing_Option' => 'Premium'
        };

        List<RES_ResidentialBundlePricingHook.AttributeAdjustment> matches =
            hook.findMatchingAdjustments(adjList, matchContext);

        Test.stopTest();

        System.assertNotEquals(null, matches, 'Should find matching adjustments');
        System.assertEquals(1, matches.size(), 'Should find exactly one Premium adjustment');
        System.assertEquals('Override', matches[0].adjustmentType, 'Should be Override type');
        System.assertEquals(5000, matches[0].adjustmentValue, 'Should have correct price');
    }

    /** Test: Find matching adjustments for a selected option with RES_Price_Option__c = Standard. */
    @isTest
    static void testFindMatchingAdjustments_Standard() {
        setupCoreData();
        insertPricingRulesAndAdjustments();

        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];

        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMap =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>();
        bundleMap.put('Bundle_001', new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', bundleProduct.Id));

        List<RES_ResidentialBundlePricingHook.AttributeAdjustment> adjList =
            hook.queryAttributeAdjustments(bundleMap).get(bundleProduct.Id);

        Map<String, String> matchContext = new Map<String, String>{
            'Pricing_Option' => 'Standard'
        };

        List<RES_ResidentialBundlePricingHook.AttributeAdjustment> matches =
            hook.findMatchingAdjustments(adjList, matchContext);

        Test.stopTest();

        System.assertNotEquals(null, matches, 'Should find matching adjustments');
        System.assertEquals(1, matches.size(), 'Should find exactly one Standard adjustment');
        System.assertEquals('Override', matches[0].adjustmentType, 'Should be Override type');
        System.assertEquals(3000, matches[0].adjustmentValue, 'Should have correct price');
    }

    /** Test: findMatchingAdjustments returns nothing on a non-matching value or a missing attribute. */
    @isTest
    static void testFindMatchingAdjustments_NoMatch() {
        setupCoreData();
        insertPricingRulesAndAdjustments();

        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];

        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMap =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>();
        bundleMap.put('Bundle_001', new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', bundleProduct.Id));
        List<RES_ResidentialBundlePricingHook.AttributeAdjustment> adjList =
            hook.queryAttributeAdjustments(bundleMap).get(bundleProduct.Id);

        List<RES_ResidentialBundlePricingHook.AttributeAdjustment> noValueMatch =
            hook.findMatchingAdjustments(adjList, new Map<String, String>{'Pricing_Option' => 'DoesNotExist'});
        List<RES_ResidentialBundlePricingHook.AttributeAdjustment> noAttributeMatch =
            hook.findMatchingAdjustments(adjList, new Map<String, String>());

        Test.stopTest();

        System.assert(noValueMatch.isEmpty(), 'A value with no matching condition should produce no matches');
        System.assert(noAttributeMatch.isEmpty(), 'An empty context (missing the matching attribute) should produce no matches');
    }

    /** Test: Query attribute adjustments, following the real Adjustment -> Rule -> Condition path. */
    @isTest
    static void testQueryAttributeAdjustments() {
        setupCoreData();
        insertPricingRulesAndAdjustments();

        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];

        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMap =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>();
        RES_ResidentialBundlePricingHook.BundleStructure bundle =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', bundleProduct.Id);
        bundleMap.put('Bundle_001', bundle);

        Map<String, List<RES_ResidentialBundlePricingHook.AttributeAdjustment>> adjustmentMap =
            hook.queryAttributeAdjustments(bundleMap);

        Test.stopTest();

        System.assertNotEquals(null, adjustmentMap, 'Adjustment map should not be null');
        System.assert(adjustmentMap.containsKey(bundleProduct.Id), 'Should have adjustments for bundle product');

        List<RES_ResidentialBundlePricingHook.AttributeAdjustment> adjustments = adjustmentMap.get(bundleProduct.Id);
        System.assertEquals(3, adjustments.size(), 'Should load 3 adjustments (Premium, Standard, Basic)');

        Boolean foundPremium = false;
        Boolean foundStandard = false;
        Boolean foundBasic = false;
        for (RES_ResidentialBundlePricingHook.AttributeAdjustment adj : adjustments) {
            System.assert(!adj.conditions.isEmpty(), 'Each adjustment should have its conditions loaded from its rule');
            String conditionValue = adj.conditions[0].StringValue;
            if (conditionValue == 'Premium') {
                foundPremium = true;
                System.assertEquals(5000, adj.adjustmentValue, 'Premium adjustment should be 5000');
            }
            if (conditionValue == 'Standard') {
                foundStandard = true;
                System.assertEquals(3000, adj.adjustmentValue, 'Standard adjustment should be 3000');
            }
            if (conditionValue == 'Basic') {
                foundBasic = true;
                System.assertEquals(20, adj.adjustmentValue, 'Basic adjustment should be 20');
            }
        }
        System.assert(foundPremium, 'Should find Premium adjustment');
        System.assert(foundStandard, 'Should find Standard adjustment');
        System.assert(foundBasic, 'Should find Basic adjustment');
    }

    /** Test: Selecting Premium applies its adjustment back onto the bundle's line and mirrors it onto the attribute node. */
    @isTest
    static void testApplyPricingToOptions_SelectedChildDrivesPricing() {
        setupCoreData();
        insertPricingRulesAndAdjustments();
        insertBundleComponentPriceOption();

        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();

        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];
        Product2 premiumOption = [SELECT Id FROM Product2 WHERE Name = :PREMIUM_NAME LIMIT 1];

        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMap =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>();

        RES_ResidentialBundlePricingHook.BundleStructure bundle =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', bundleProduct.Id);
        List<Object> bundleNodePath = new List<Object>{'QuoteId_123', 'Bundle_001'};
        bundle.nodePath = bundleNodePath;
        List<Object> childNodePath = new List<Object>{'QuoteId_123', 'LineId_456'};
        bundle.addChildOption(new RES_ResidentialBundlePricingHook.OptionItem(
            'Child_001', premiumOption.Id, childNodePath, 'Bundle_001/Child_001'
        ));
        bundleMap.put('Bundle_001', bundle);

        Map<String, List<RES_ResidentialBundlePricingHook.AttributeAdjustment>> bundleAdjustmentsMap =
            hook.queryAttributeAdjustments(bundleMap);
        Map<String, String> childProductPriceOptionMap = hook.queryChildOptionPriceValues(bundleMap);

        // An existing Pricing_Option attribute node so the "mirror the selection" branch is exercised too
        List<Object> attrNodePath = new List<Object>{'QuoteId_123', 'Bundle_001', 'AttrNode_001'};
        Map<String, List<Object>> attributeNodePathMap = new Map<String, List<Object>>{
            'Bundle_001:Pricing_Option' => attrNodePath
        };
        Map<String, Map<String, String>> itemAttributeMap = new Map<String, Map<String, String>>();

        List<Map<String, Object>> updates = hook.applyPricingToOptions(
            bundleMap, itemAttributeMap, bundleAdjustmentsMap, childProductPriceOptionMap,
            attributeNodePathMap, new Map<String, Decimal>(),
            new Map<Id, Decimal>(), new Set<Id>(), new Map<Id, Decimal>()
        );

        Test.stopTest();

        System.assert(!updates.isEmpty(), 'Should produce at least one price update for the bundle');

        Boolean foundOverridePrice = false;
        Boolean foundAttributeMirror = false;
        for (Map<String, Object> updateEntry : updates) {
            Map<String, Object> updateNodePath = (Map<String, Object>) updateEntry.get('nodePath');
            for (Object attrObj : (List<Object>) updateEntry.get('attributes')) {
                Map<String, Object> attr = (Map<String, Object>) attrObj;
                if (attr.get('attributeName') == 'PartnerUnitPrice' && attr.get('attributeValue') == 5000) {
                    foundOverridePrice = true;
                    System.assertEquals(bundleNodePath, updateNodePath.get('dataPath'),
                        'Price update should target the bundle node, not the selected child option');
                }
                if (attr.get('attributeName') == 'AttributeValue' && attr.get('attributeValue') == 'Premium') {
                    foundAttributeMirror = true;
                    System.assertEquals(attrNodePath, updateNodePath.get('dataPath'),
                        'Attribute mirror update should target the existing Pricing_Option node');
                }
            }
        }
        System.assert(foundOverridePrice, 'Premium option should receive the Premium Pricing adjustment (5000)');
        System.assert(foundAttributeMirror, 'Should mirror the selection onto the existing Pricing_Option attribute node');
    }

    /** Test: applyPricingToOptions computes and applies the service charge alongside the bundle's own price update. */
    @isTest
    static void testApplyPricingToOptions_ServiceCharge() {
        // No insertServiceChargeComponent() needed - queryServiceChargeProductIds matches by Product2.Name alone
        setupCoreData();
        insertPricingRulesAndAdjustments();
        insertBundleComponentPriceOption();
        insertServiceChargeRateAttribute();

        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];
        Product2 premiumOption = [SELECT Id FROM Product2 WHERE Name = :PREMIUM_NAME LIMIT 1];
        Product2 serviceCharge = [SELECT Id FROM Product2 WHERE Name = :SERVICE_CHARGE_NAME LIMIT 1];

        RES_ResidentialBundlePricingHook.BundleStructure bundle =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', bundleProduct.Id);
        bundle.nodePath = new List<Object>{'QuoteId_123', 'Bundle_001'};
        List<Object> childNodePath = new List<Object>{'QuoteId_123', 'LineId_456'};
        List<Object> serviceChargeNodePath = new List<Object>{'QuoteId_123', 'LineId_789'};
        bundle.addChildOption(new RES_ResidentialBundlePricingHook.OptionItem(
            'Child_001', premiumOption.Id, childNodePath, 'Bundle_001/Child_001'
        ));
        bundle.addChildOption(new RES_ResidentialBundlePricingHook.OptionItem(
            'SC_001', serviceCharge.Id, serviceChargeNodePath, 'Bundle_001/SC_001'
        ));

        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMap =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>{'Bundle_001' => bundle};

        Map<String, List<RES_ResidentialBundlePricingHook.AttributeAdjustment>> bundleAdjustmentsMap =
            hook.queryAttributeAdjustments(bundleMap);
        Map<String, String> childProductPriceOptionMap = hook.queryChildOptionPriceValues(bundleMap);
        Map<Id, Decimal> netSaleableAreaMap = hook.queryNetSaleableAreaByProduct(bundleMap);
        Set<Id> serviceChargeProductIds = hook.queryServiceChargeProductIds(bundleMap);
        Map<Id, Decimal> serviceChargeRateMap = hook.queryServiceChargeRateByProduct(bundleMap);

        List<Map<String, Object>> updates = hook.applyPricingToOptions(
            bundleMap, new Map<String, Map<String, String>>(), bundleAdjustmentsMap, childProductPriceOptionMap,
            new Map<String, List<Object>>(), new Map<String, Decimal>(),
            netSaleableAreaMap, serviceChargeProductIds, serviceChargeRateMap
        );

        Test.stopTest();

        Boolean foundServiceCharge = false;
        Boolean foundBundlePrice = false;
        for (Map<String, Object> updateEntry : updates) {
            Map<String, Object> updateNodePath = (Map<String, Object>) updateEntry.get('nodePath');
            for (Object attrObj : (List<Object>) updateEntry.get('attributes')) {
                Map<String, Object> attr = (Map<String, Object>) attrObj;
                if (attr.get('attributeName') == 'RES_Service_Charge_Amount__c') {
                    foundServiceCharge = true;
                    System.assertEquals(149000, attr.get('attributeValue'), 'Service charge should be rate (149) x area (1000)');
                    System.assertEquals(serviceChargeNodePath, updateNodePath.get('dataPath'),
                        'Service charge update should target the Service Charge component\'s own line');
                }
                if (attr.get('attributeName') == 'PartnerUnitPrice') {
                    foundBundlePrice = true;
                }
            }
        }
        System.assert(foundServiceCharge, 'Should compute and apply the service charge onto its own line');
        System.assert(foundBundlePrice, 'Should still apply the bundle\'s own Payment-Plan-driven price update');
    }

    /** Test: executeInternal end-to-end against real bundle/adjustment/SC_RATE data with a fabricated context provider. */
    @isTest
    static void testExecuteInternal_EndToEndAppliesPremiumAndServiceCharge() {
        setupCoreData();
        insertPricingRulesAndAdjustments();
        insertBundleComponentPriceOption();
        insertServiceChargeRateAttribute();

        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];
        Product2 premiumOption = [SELECT Id FROM Product2 WHERE Name = :PREMIUM_NAME LIMIT 1];
        Product2 serviceCharge = [SELECT Id FROM Product2 WHERE Name = :SERVICE_CHARGE_NAME LIMIT 1];

        List<Object> bundleDataPath = new List<Object>{'ctx123', 'QuoteId_1', 'LineCtx_Bundle'};
        List<Object> childDataPath = new List<Object>{'ctx123', 'QuoteId_1', 'LineCtx_Child'};
        List<Object> scDataPath = new List<Object>{'ctx123', 'QuoteId_1', 'LineCtx_SC'};

        List<Object> items = new List<Object>{
            RES_FakeIndustriesContextProvider.buildLineItemNode('Bundle_001', 'Bundle_001', bundleProduct.Id, bundleDataPath, null),
            RES_FakeIndustriesContextProvider.buildLineItemNode('Child_001', 'Bundle_001/Child_001', premiumOption.Id, childDataPath, null),
            RES_FakeIndustriesContextProvider.buildLineItemNode('SC_001', 'Bundle_001/SC_001', serviceCharge.Id, scDataPath, null)
        };

        RES_FakeIndustriesContextProvider fakeProvider = new RES_FakeIndustriesContextProvider();
        fakeProvider.queryTagsResultToReturn = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => items,
                'SalesTransactionItemAttribute' => new List<Object>()
            }
        };

        Test.startTest();
        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        RevSignaling.TransactionResponse response = hook.executeInternal('ctx123', fakeProvider);
        Test.stopTest();

        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, response.status, 'Should succeed with real matching data');
        System.assertEquals(1, fakeProvider.updateContextAttributesCallCount, 'Should submit exactly one update payload');

        Map<String, Object> submittedInput = fakeProvider.updateContextAttributesInput;
        System.assertEquals('ctx123', submittedInput.get('contextId'), 'Update payload should carry the original contextId');

        Boolean foundOverridePrice = false;
        Boolean foundServiceCharge = false;
        for (Object updateObj : (List<Object>) submittedInput.get('nodePathAndAttributes')) {
            Map<String, Object> updateEntry = (Map<String, Object>) updateObj;
            for (Object attrObj : (List<Object>) updateEntry.get('attributes')) {
                Map<String, Object> attr = (Map<String, Object>) attrObj;
                if (attr.get('attributeName') == 'PartnerUnitPrice' && attr.get('attributeValue') == 5000) {
                    foundOverridePrice = true;
                }
                if (attr.get('attributeName') == 'RES_Service_Charge_Amount__c' && attr.get('attributeValue') == 149000) {
                    foundServiceCharge = true;
                }
            }
        }
        System.assert(foundOverridePrice, 'Should apply the Premium override price onto the bundle line');
        System.assert(foundServiceCharge, 'Should apply the computed service charge onto its own component line');
    }

    /** Test: matchesAllConditions - AND logic across multiple conditions, 'notequals', and an unsupported operator. */
    @isTest
    static void testMatchesAllConditions_MultipleAndOperators() {
        // The org only allows 'equals' on a real inserted condition, so wire AttributeDefinition via putSObject instead
        List<AttributeDefinition> existingPricingOptionAttrs = [
            SELECT Id, DeveloperName FROM AttributeDefinition WHERE DeveloperName = 'Pricing_Option' LIMIT 1
        ];
        AttributeDefinition pricingOptionAttr;
        if (!existingPricingOptionAttrs.isEmpty()) {
            pricingOptionAttr = existingPricingOptionAttrs[0];
        } else {
            pricingOptionAttr = new AttributeDefinition(
                Name = 'RES Test Matching Pricing Option', Label = 'RES Test Matching Pricing Option',
                DeveloperName = 'Pricing_Option', DataType = 'Text', IsActive = true
            );
            insert pricingOptionAttr;
        }

        AttributeAdjustmentCondition notEqualsCondition = new AttributeAdjustmentCondition(
            AttributeDefinitionId = pricingOptionAttr.Id, Operator = 'notequals', StringValue = 'Basic'
        );
        notEqualsCondition.putSObject('AttributeDefinition', pricingOptionAttr);

        AttributeAdjustmentCondition unsupportedOpCondition = new AttributeAdjustmentCondition(
            AttributeDefinitionId = pricingOptionAttr.Id, Operator = 'greaterthan', StringValue = '5'
        );
        unsupportedOpCondition.putSObject('AttributeDefinition', pricingOptionAttr);

        Test.startTest();

        RES_ResidentialBundlePricingHook.AttributeAdjustment adjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_001', 'Test Adjustment', 'Override', 1000, null,
                new List<AttributeAdjustmentCondition>{notEqualsCondition}
            );

        Boolean matchesNotEqualsTrue = adjustment.matchesAllConditions(new Map<String, String>{'Pricing_Option' => 'Premium'});
        Boolean matchesNotEqualsFalse = adjustment.matchesAllConditions(new Map<String, String>{'Pricing_Option' => 'Basic'});

        RES_ResidentialBundlePricingHook.AttributeAdjustment unsupportedOperatorAdjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_002', 'Unsupported Operator', 'Override', 1000, null,
                new List<AttributeAdjustmentCondition>{unsupportedOpCondition}
            );
        Boolean matchesUnsupportedOperator = unsupportedOperatorAdjustment.matchesAllConditions(
            new Map<String, String>{'Pricing_Option' => '10'}
        );

        RES_ResidentialBundlePricingHook.AttributeAdjustment noConditionsAdjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_003', 'No Conditions', 'Override', 1000, null, null
            );
        Boolean matchesNoConditions = noConditionsAdjustment.matchesAllConditions(
            new Map<String, String>{'Pricing_Option' => 'Premium'}
        );

        // AttributeDefinition genuinely null (never wired via putSObject) - attributeName resolves to null
        AttributeAdjustmentCondition noAttributeDefinitionCondition =
            new AttributeAdjustmentCondition(Operator = 'equals', StringValue = 'Premium');
        RES_ResidentialBundlePricingHook.AttributeAdjustment nullAttributeDefinitionAdjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_004', 'Null AttributeDefinition', 'Override', 1000, null,
                new List<AttributeAdjustmentCondition>{noAttributeDefinitionCondition}
            );
        Boolean matchesNullAttributeDefinition = nullAttributeDefinitionAdjustment.matchesAllConditions(
            new Map<String, String>{'Pricing_Option' => 'Premium'}
        );

        // Key present but mapped to null - exercises conditionMatchesValue's itemValue==null branch
        AttributeAdjustmentCondition equalsCondition = new AttributeAdjustmentCondition(
            AttributeDefinitionId = pricingOptionAttr.Id, Operator = 'equals', StringValue = 'Premium'
        );
        equalsCondition.putSObject('AttributeDefinition', pricingOptionAttr);
        RES_ResidentialBundlePricingHook.AttributeAdjustment nullValueAdjustment =
            new RES_ResidentialBundlePricingHook.AttributeAdjustment(
                'Adj_005', 'Null Item Value', 'Override', 1000, null,
                new List<AttributeAdjustmentCondition>{equalsCondition}
            );
        Map<String, String> itemAttributesWithNullValue = new Map<String, String>{'Pricing_Option' => null};
        Boolean matchesNullItemValue = nullValueAdjustment.matchesAllConditions(itemAttributesWithNullValue);

        Test.stopTest();

        System.assertEquals(true, matchesNotEqualsTrue, 'notequals should match when the value differs');
        System.assertEquals(false, matchesNotEqualsFalse, 'notequals should not match when the value is equal');
        System.assertEquals(false, matchesUnsupportedOperator, 'An unsupported operator should never match');
        System.assertEquals(false, matchesNoConditions, 'An adjustment with no conditions can never match');
        System.assertEquals(false, matchesNullAttributeDefinition, 'A condition with no AttributeDefinition can never match');
        System.assertEquals(false, matchesNullItemValue, 'A null item attribute value can never match');
    }

    /** Test: queryServiceChargeRateByProduct reads SC_RATE from catalog config (org-wide-unique name, needs SeeAllData). */
    @isTest
    static void testQueryServiceChargeRateByProduct() {
        setupCoreData();
        insertServiceChargeRateAttribute();

        Test.startTest();

        RES_ResidentialBundlePricingHook hook = new RES_ResidentialBundlePricingHook();
        Product2 bundleProduct = [SELECT Id FROM Product2 WHERE Name = :BUNDLE_NAME LIMIT 1];

        RES_ResidentialBundlePricingHook.BundleStructure bundle =
            new RES_ResidentialBundlePricingHook.BundleStructure('Bundle_001', bundleProduct.Id);
        Map<String, RES_ResidentialBundlePricingHook.BundleStructure> bundleMap =
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>{'Bundle_001' => bundle};

        Map<Id, Decimal> rateMap = hook.queryServiceChargeRateByProduct(bundleMap);

        Map<Id, Decimal> emptyResult = hook.queryServiceChargeRateByProduct(
            new Map<String, RES_ResidentialBundlePricingHook.BundleStructure>()
        );

        Test.stopTest();

        System.assertEquals(149, rateMap.get(bundleProduct.Id), 'Should load SC_RATE = 149 from catalog config');
        System.assert(emptyResult.isEmpty(), 'No bundle product IDs should yield an empty map');
    }
}
