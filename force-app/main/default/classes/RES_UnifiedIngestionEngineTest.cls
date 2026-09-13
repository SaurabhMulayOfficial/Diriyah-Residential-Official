/**
 * Test class for RES_UnifiedIngestionEngine.
 */
@IsTest
private class RES_UnifiedIngestionEngineTest {

    private static final String LAYOUT_CODE = 'RESIDENTIAL_SALES';
    private static final String VALID_FAMILY_VALUE = '1003';

    /**
     * Apex tests cannot see pre-existing org data (ProductClassification,
     * PriceAdjustmentSchedule) unless it is created inside the test's own
     * transaction, so the classification and schedule the RESIDENTIAL_SALES
     * layout names are created here rather than assumed to already exist.
     * Custom metadata (RES_Ingestion_Layout__mdt) IS visible in tests, so the
     * names are read from config instead of hardcoded, keeping this in sync
     * with whatever the layout is actually configured to point at.
     */
    @TestSetup
    static void setupReferenceData() {
        RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(LAYOUT_CODE);
        System.assert(layout != null, 'RESIDENTIAL_SALES layout must be configured in RES_Ingestion_Layout__mdt');

        if (String.isNotBlank(layout.productClassification)) {
            insert new ProductClassification(
                Name   = layout.productClassification,
                Code   = layout.productClassification.replaceAll('[^a-zA-Z0-9]', '_').toUpperCase(),
                Status = 'Active'
            );
        }
        if (String.isNotBlank(layout.priceAdjustmentSchedule)) {
            insert new PriceAdjustmentSchedule(
                Name             = layout.priceAdjustmentSchedule,
                IsActive         = true,
                ScheduleType     = 'Attribute',
                AdjustmentMethod = 'Range',
                EffectiveFrom    = Datetime.newInstanceGmt(Date.today().addYears(-1), Time.newInstance(0, 0, 0, 0))
            );
        }
    }

    // ==================================================================
    // Helpers
    // ==================================================================

    private static RES_Product_Staging__c baseRow(String code, String catalogName, String buildingName) {
        return new RES_Product_Staging__c(
            RES_Product_Code__c  = code,
            RES_Catalog_Name__c  = catalogName,
            RES_Building_Name__c = buildingName,
            RES_Product_Name__c  = 'Test Unit ' + code,
            RES_Usage_Type__c    = VALID_FAMILY_VALUE
        );
    }

    private static Id productRecordTypeIdIfAny() {
        Schema.RecordTypeInfo rt = Product2.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get('RES_Residential_Sales');
        return (rt != null && rt.isAvailable()) ? rt.getRecordTypeId() : null;
    }

    // ==================================================================
    // Happy path: two new products, pricing options (Y100/Y101/Y102),
    // computed + plain attributes, measurements, plus row-level errors,
    // plus a second execute() call (new engine instance) that reuses the
    // same catalog/category/selling model so the "already exists" query
    // branches get exercised too.
    // ==================================================================
    @IsTest
    static void testHappyPath_NewProductsPricingOptionsAttributesAndErrors() {
        String catalog  = 'WadiSafar1';
        String building = 'Villa Type A';

        RES_Product_Staging__c y100 = baseRow('UNIT-100', catalog, building);
        y100.RES_Condition_Type__c       = 'Y100';
        y100.RES_Condition_Price__c      = 1500000;
        y100.RES_Condition_Valid_From__c = Date.today().addDays(2);
        y100.RES_Service_Charge_Rate__c = 50;
        y100.RES_Parameter_1__c         = 'Z006'; // matches Measurement_Area sourceCode
        y100.RES_Area__c                = 120;

        RES_Product_Staging__c y101 = baseRow('UNIT-100', catalog, building);
        y101.RES_Condition_Type__c  = 'Y101';
        y101.RES_Condition_Price__c = 1550000;

        RES_Product_Staging__c y102 = baseRow('UNIT-100', catalog, building);
        y102.RES_Condition_Type__c  = 'Y102';
        y102.RES_Condition_Price__c = 1600000;

        // Second product, same catalog, different building -> new category.
        RES_Product_Staging__c product2 = baseRow('UNIT-200', catalog, 'Villa Type B');
        product2.RES_Condition_Type__c  = 'Y100';
        product2.RES_Condition_Price__c = 900000;

        // Row error: blank product code.
        RES_Product_Staging__c blankCode = baseRow(null, catalog, building);

        // Row error: priced row (no condition type -> treated as priced) with no price at all.
        // Also carries an invalid Picklist_Safe value, so the mapping-rejected branch fires too.
        RES_Product_Staging__c noPrice = baseRow('UNIT-300', catalog, building);
        noPrice.RES_Residential_Type__c = 'BOGUS999';

        List<RES_Product_Staging__c> scope = new List<RES_Product_Staging__c>{
            y100, y101, y102, product2, blankCode, noPrice
        };
        insert scope;

        Test.startTest();
        RES_UnifiedIngestionEngine engine = new RES_UnifiedIngestionEngine(LAYOUT_CODE);
        engine.execute(null, scope);
        Test.stopTest();

        // ---- Product2 ----
        List<Product2> products = [
            SELECT Id, ProductCode, Name, IsActive, Family, RecordTypeId
            FROM Product2
            WHERE RES_Product_External_ID__c IN ('UNIT-100', 'UNIT-200', 'UNIT-300')
        ];
        Map<String, Product2> productByCode = new Map<String, Product2>();
        for (Product2 p : products) productByCode.put(p.ProductCode, p);

        Assert.areEqual(3, products.size(), 'Expected 3 products (UNIT-100, UNIT-200, UNIT-300)');
        Product2 unit100 = productByCode.get('UNIT-100');
        Assert.isNotNull(unit100, 'UNIT-100 should have been created');
        Assert.areEqual(false, unit100.IsActive, 'New products default to IsActive=false via literal mapping');
        Assert.areEqual(VALID_FAMILY_VALUE, unit100.Family, 'Family should be set via Picklist_Safe mapping');

        Id expectedRt = productRecordTypeIdIfAny();
        if (expectedRt != null) {
            Assert.areEqual(expectedRt, unit100.RecordTypeId, 'Record type should be applied for new products');
        }

        // ---- ProductCatalog / ProductCategory ----
        List<ProductCatalog> catalogs = [SELECT Id, Code FROM ProductCatalog WHERE Code = :('BE-' + catalog)];
        Assert.areEqual(1, catalogs.size(), 'Exactly one catalog should be created for the shared catalog name');

        List<ProductCategory> categories = [
            SELECT Id, Code FROM ProductCategory
            WHERE Code IN (:('BLD-' + catalog + '-' + building), :('BLD-' + catalog + '-Villa Type B'))
        ];
        Assert.areEqual(2, categories.size(), 'Two categories should be created (one per building)');

        Assert.areEqual(1, [SELECT COUNT() FROM ProductCategoryProduct WHERE ProductId = :unit100.Id]);

        // ---- ProductDisqualification (new products only) ----
        Assert.areEqual(3, [SELECT COUNT() FROM ProductDisqualification WHERE ProductId IN :productByCode.values()]);

        // ---- Selling model + link ----
        List<ProductSellingModel> psms = [
            SELECT Id, SellingModelType FROM ProductSellingModel WHERE Name LIKE 'SAP Y100%'
        ];
        Assert.isFalse(psms.isEmpty(), 'A single OneTime selling model should be created for Y100');
        Assert.areEqual('OneTime', psms[0].SellingModelType);
        Assert.areEqual(3, [
            SELECT COUNT() FROM ProductSellingModelOption WHERE ProductSellingModelId = :psms[0].Id
        ], 'UNIT-100, UNIT-200, and UNIT-300 should all be linked to the shared OneTime selling model');

        // ---- PricebookEntry: base price is 0 for Attribute_Based_Adjustment handling ----
        List<PricebookEntry> pbes = [
            SELECT Id, UnitPrice, IsActive FROM PricebookEntry
            WHERE Product2Id = :unit100.Id AND Pricebook2Id = :Test.getStandardPricebookId()
        ];
        Assert.areEqual(1, pbes.size());
        Assert.areEqual(0, pbes[0].UnitPrice, 'Attribute_Based_Adjustment handling should zero out the base price');
        Assert.areEqual(false, pbes[0].IsActive, 'PricebookEntry should mirror the (inactive) product');

        // ---- Selector attribute (Pricing Option) + picklist values ----
        List<AttributeDefinition> selectorDefs = [
            SELECT Id, PicklistId FROM AttributeDefinition WHERE Name = 'Pricing Option'
        ];
        Assert.areEqual(1, selectorDefs.size());
        Assert.areEqual(3, [
            SELECT COUNT() FROM AttributePicklistValue WHERE PicklistId = :selectorDefs[0].PicklistId
        ], 'Option 1/2/3 should all be added to the picklist');

        Assert.areEqual(1, [
            SELECT COUNT() FROM ProductAttributeDefinition
            WHERE Product2Id = :unit100.Id AND AttributeDefinitionId = :selectorDefs[0].Id AND DefaultValue = 'Option 1'
        ], 'Selector attribute should default to the primary conditions selector value');

        // ---- Attribute-based adjustment rules/conditions/adjustments ----
        List<AttributeBasedAdjRule> rules = [
            SELECT Id, Name FROM AttributeBasedAdjRule WHERE Name LIKE 'UNIT-100 ::%'
        ];
        Assert.areEqual(3, rules.size(), 'One rule per selector option for UNIT-100');
        Set<Id> ruleIds = new Map<Id, AttributeBasedAdjRule>(rules).keySet();
        Assert.areEqual(3, [SELECT COUNT() FROM AttributeAdjustmentCondition WHERE AttributeBasedAdjRuleId IN :ruleIds]);

        List<AttributeBasedAdjustment> adjustments = [
            SELECT Id, AdjustmentValue, AdjustmentType FROM AttributeBasedAdjustment
            WHERE AttributeBasedAdjRuleId IN :ruleIds
        ];
        Assert.areEqual(3, adjustments.size());
        Set<Decimal> values = new Set<Decimal>();
        for (AttributeBasedAdjustment a : adjustments) {
            Assert.areEqual('Override', a.AdjustmentType);
            // Normalize scale before adding to the set: AdjustmentValue comes back from the
            // database at whatever scale the field is defined with, and Set<Decimal>
            // containment is scale-sensitive even though Decimal.equals() is not.
            values.add(a.AdjustmentValue.setScale(0));
        }
        Assert.isTrue(values.containsAll(new Set<Decimal>{1500000, 1550000, 1600000}));

        // ---- Computed + plain product attributes (Service Charge / Service Charge Rate) ----
        Assert.areEqual(1, [
            SELECT COUNT() FROM ProductAttributeDefinition pad
            WHERE pad.Product2Id = :unit100.Id
            AND pad.AttributeDefinitionId IN (SELECT Id FROM AttributeDefinition WHERE Name = 'Service Charge Rate')
            AND pad.DefaultValue = '50.00'
        ], 'addTargetMapAttributes() scales every Product_Attribute/_Computed value to 2 decimal places');
        Assert.areEqual(1, [
            SELECT COUNT() FROM ProductAttributeDefinition pad
            WHERE pad.Product2Id = :unit100.Id
            AND pad.AttributeDefinitionId IN (SELECT Id FROM AttributeDefinition WHERE Name = 'Service Charge')
            AND pad.DefaultValue = '6000.00'
        ], 'Service Charge should be computed as rate (50) * Area measurement (120)');

        // ---- Measurement (Area, code Z006) ----
        Assert.areEqual(1, [
            SELECT COUNT() FROM RES_Measurement__c
            WHERE RES_Product__c = :unit100.Id AND RES_Measurement_Type__c = 'Z006' AND RES_Measurement_Amount__c = 120
        ]);

        // ---- Row-level error handling ----
        Map<Id, RES_Product_Staging__c> finalRows = new Map<Id, RES_Product_Staging__c>(
            [SELECT Id, RES_Processing_Status__c, RES_Error_Log__c FROM RES_Product_Staging__c WHERE Id IN :scope]
        );
        Assert.areEqual('Error', finalRows.get(blankCode.Id).RES_Processing_Status__c);
        Assert.isTrue(finalRows.get(blankCode.Id).RES_Error_Log__c.contains('Product Code is blank'));

        Assert.areEqual('Error', finalRows.get(noPrice.Id).RES_Processing_Status__c);
        Assert.isTrue(finalRows.get(noPrice.Id).RES_Error_Log__c.contains('No Price or Condition Price on the row'));
        Assert.isTrue(finalRows.get(noPrice.Id).RES_Error_Log__c.contains('is not an active value on'),
            'An unmatched Picklist_Safe value should add its own row error alongside the price error');

        Assert.areEqual('Completed', finalRows.get(y100.Id).RES_Processing_Status__c);

        // ---- Second execute() call: reuse catalog/category/selling model to hit "already exists" branches ----
        RES_Product_Staging__c product3 = baseRow('UNIT-400', catalog, building); // same catalog+building as UNIT-100
        product3.RES_Condition_Type__c  = 'Y100';
        product3.RES_Condition_Price__c = 700000;
        insert product3;

        RES_UnifiedIngestionEngine secondEngine = new RES_UnifiedIngestionEngine(LAYOUT_CODE);
        secondEngine.execute(null, new List<RES_Product_Staging__c>{ product3 });

        Assert.areEqual(1, [SELECT COUNT() FROM ProductCatalog WHERE Code = :('BE-' + catalog)],
            'Catalog should be reused, not duplicated, across a fresh engine instance');
        Assert.areEqual(1, [
            SELECT COUNT() FROM ProductCategory WHERE Code = :('BLD-' + catalog + '-' + building)
        ], 'Category should be reused, not duplicated');
        Assert.areEqual(1, [SELECT COUNT() FROM ProductSellingModel WHERE Name LIKE 'SAP Y100%'],
            'Selling model should be reused (found via DAO query on a fresh engine instance), not duplicated');

        // ---- Third pass: reuse the SAME engine instance and re-process UNIT-400 (plus a
        // changed re-run of UNIT-100) to exercise every "record already exists" / "value
        // changed, needs update" branch across links, disqualification, pricing-option
        // rules/conditions/adjustments, attribute definitions, and measurements.
        // Y100 is Attribute_Based_Adjustment, so PricebookEntry.UnitPrice is always zeroed;
        // IsActive is the only thing on it that a re-run can change, hence flipping it here.
        update new Product2(Id = unit100.Id, IsActive = true);

        RES_Product_Staging__c y100Rerun = baseRow('UNIT-100', catalog, building);
        y100Rerun.RES_Condition_Type__c      = 'Y100';
        y100Rerun.RES_Condition_Price__c     = 1600000;
        y100Rerun.RES_Service_Charge_Rate__c = 60;
        y100Rerun.RES_Parameter_1__c         = 'Z006';
        y100Rerun.RES_Area__c                = 150;

        RES_Product_Staging__c product3Rerun = baseRow('UNIT-400', catalog, building);
        product3Rerun.RES_Condition_Type__c      = 'Y100';
        product3Rerun.RES_Condition_Price__c     = 750000;
        product3Rerun.RES_Service_Charge_Rate__c = 55;
        product3Rerun.RES_Parameter_1__c         = 'Z006';
        product3Rerun.RES_Area__c                = 120;
        insert new List<RES_Product_Staging__c>{ y100Rerun, product3Rerun };

        secondEngine.execute(null, new List<RES_Product_Staging__c>{ y100Rerun, product3Rerun });

        PricebookEntry rerunPbe = [
            SELECT UnitPrice, IsActive FROM PricebookEntry
            WHERE Product2Id = :unit100.Id AND Pricebook2Id = :Test.getStandardPricebookId()
        ];
        Assert.areEqual(true, rerunPbe.IsActive,
            'Re-running after the product was activated should update the existing PricebookEntry');

        Assert.areEqual(1, [
            SELECT COUNT() FROM ProductAttributeDefinition pad
            WHERE pad.Product2Id = :unit100.Id
            AND pad.AttributeDefinitionId IN (SELECT Id FROM AttributeDefinition WHERE Name = 'Service Charge')
            AND pad.DefaultValue = '9000.00'
        ], 'Service Charge should be recomputed and updated in place on a re-run with a changed rate/area');

        Assert.areEqual(1, [
            SELECT COUNT() FROM RES_Measurement__c
            WHERE RES_Product__c = :unit100.Id AND RES_Measurement_Type__c = 'Z006' AND RES_Measurement_Amount__c = 150
        ], 'The Area measurement should be updated in place on a re-run with a changed value');

        Product2 unit400 = [SELECT Id FROM Product2 WHERE RES_Product_External_ID__c = 'UNIT-400'];
        Assert.areEqual(1, [SELECT COUNT() FROM ProductDisqualification WHERE ProductId = :unit400.Id],
            'Re-running the same still-new-tracked product must not duplicate its disqualification record');
        Assert.areEqual(1, [SELECT COUNT() FROM ProductCategoryProduct WHERE ProductId = :unit400.Id],
            'Re-running must not duplicate the category link');
        Assert.areEqual(1, [SELECT COUNT() FROM ProductSellingModelOption WHERE Product2Id = :unit400.Id],
            'Re-running must not duplicate the selling-model link');
        Assert.areEqual(1, [SELECT COUNT() FROM AttributeBasedAdjRule WHERE Name = 'UNIT-400 :: Option 1'],
            'Re-running must not duplicate the pricing-option rule');

        List<AttributeBasedAdjustment> unit400Adjustments = [
            SELECT AdjustmentValue FROM AttributeBasedAdjustment WHERE ProductId = :unit400.Id
        ];
        Assert.areEqual(1, unit400Adjustments.size(), 'Re-running must not duplicate the adjustment');
        Assert.areEqual(750000, unit400Adjustments[0].AdjustmentValue.setScale(0),
            'Re-running with a changed price should update the existing adjustment rather than duplicate it');
    }

    // ==================================================================
    // Missing ProductClassification: the layout still names one, but the record
    // itself is gone, so resolveClassification() must fail closed for both the
    // attribute pipeline and the pricing-option pipeline in the same run. Also
    // covers the Product_Attribute_Computed "no matching measurement" branch and
    // the Attribute_Based_Adjustment "no price on the row" branch.
    // ==================================================================
    @IsTest
    static void testMissingProductClassification_SkipsAttributesAndPricingOptions() {
        RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(LAYOUT_CODE);
        delete [SELECT Id FROM ProductClassification WHERE Name = :layout.productClassification];

        // Attribute_Based_Adjustment (non-primary), no price anywhere on the row.
        RES_Product_Staging__c noPriceAdjustment = baseRow('CLS-100', 'ClsCat', 'ClsBldg');
        noPriceAdjustment.RES_Condition_Type__c = 'Y101';

        // Primary condition (has a price, so pricing options are attempted) plus a
        // Product_Attribute_Computed field whose Parameter-1 code matches nothing.
        RES_Product_Staging__c withAttrs = baseRow('CLS-200', 'ClsCat', 'ClsBldg');
        withAttrs.RES_Condition_Type__c      = 'Y100';
        withAttrs.RES_Condition_Price__c     = 500000;
        withAttrs.RES_Service_Charge_Rate__c = 30;
        withAttrs.RES_Parameter_1__c         = 'NOT_A_REAL_CODE';
        withAttrs.RES_Area__c                = 10;

        List<RES_Product_Staging__c> scope = new List<RES_Product_Staging__c>{ noPriceAdjustment, withAttrs };
        insert scope;

        Test.startTest();
        RES_UnifiedIngestionEngine engine = new RES_UnifiedIngestionEngine(LAYOUT_CODE);
        engine.execute(null, scope);
        Test.stopTest();

        Boolean sawClassificationError = false;
        Boolean sawParameterMismatchError = false;
        for (String e : engine.errorSamples) {
            if (e.contains('ProductClassification')) sawClassificationError = true;
            if (e.contains('does not match any mapped measurement')) sawParameterMismatchError = true;
        }
        Assert.isTrue(sawClassificationError, 'A missing ProductClassification must be recorded as an error');
        Assert.isTrue(sawParameterMismatchError, 'An unmatched Parameter-1 code must be recorded as an error');

        Product2 cls200 = [SELECT Id FROM Product2 WHERE RES_Product_External_ID__c = 'CLS-200'];
        Assert.areEqual(0, [SELECT COUNT() FROM ProductAttributeDefinition WHERE Product2Id = :cls200.Id],
            'No attribute should be written when the classification cannot be resolved');
        Assert.areEqual(0, [SELECT COUNT() FROM AttributeBasedAdjRule WHERE Name LIKE 'CLS-200 ::%'],
            'No pricing-option rule should be written when the classification cannot be resolved');

        RES_Product_Staging__c refreshedNoPrice = [
            SELECT RES_Error_Log__c FROM RES_Product_Staging__c WHERE Id = :noPriceAdjustment.Id
        ];
        Assert.isTrue(refreshedNoPrice.RES_Error_Log__c.contains('carries no price'),
            'A priced-adjustment row with no price should record its own row error');
    }

    // ==================================================================
    // Update path: existing product, skipOnUpdate literals must NOT fire.
    // ==================================================================
    @IsTest
    static void testUpdateExistingProduct_SkipOnUpdateLiteralsAreSkipped() {
        Product2 existing = new Product2(
            RES_Product_External_ID__c = 'UNIT-500',
            ProductCode                = 'UNIT-500',
            Name                       = 'Original Name',
            IsActive                   = true
        );
        insert existing;

        RES_Product_Staging__c row = baseRow('UNIT-500', 'WadiSafar2', 'Villa Type C');
        row.RES_Product_Name__c = 'Updated Name';
        insert row;

        Test.startTest();
        RES_UnifiedIngestionEngine engine = new RES_UnifiedIngestionEngine(LAYOUT_CODE);
        engine.execute(null, new List<RES_Product_Staging__c>{ row });
        Test.stopTest();

        Product2 updated = [SELECT IsActive, Name, RES_Unit_Status__c FROM Product2 WHERE Id = :existing.Id];
        Assert.areEqual(true, updated.IsActive, 'IsActive literal (skipOnUpdate) must not override an existing product');
        Assert.areEqual('Updated Name', updated.Name, 'Non-skip Direct mapping should still apply on update');

        Assert.areEqual(0, [SELECT COUNT() FROM ProductDisqualification WHERE ProductId = :existing.Id],
            'Existing (non-new) products must not get a disqualification record');
    }

    // ==================================================================
    // Unknown layout code: exercises the "no config found" guard clauses,
    // plus cache-hit branches on resolveTargetPricebooks / disqualifyNewProducts.
    // ==================================================================
    @IsTest
    static void testUnknownLayoutCode_GuardClauses() {
        RES_Product_Staging__c row = baseRow('UNIT-600', 'AdHocCatalog', 'Ad Hoc Building');
        insert row;

        Test.startTest();
        RES_UnifiedIngestionEngine engine = new RES_UnifiedIngestionEngine('DOES_NOT_EXIST');
        engine.execute(null, new List<RES_Product_Staging__c>{ row });

        // Calling directly a second time should hit the "already resolved" cache branch.
        List<Id> firstCall   = engine.resolveTargetPricebooks();
        List<Id> secondCall = engine.resolveTargetPricebooks();
        Test.stopTest();

        Assert.areEqual(firstCall, secondCall, 'resolveTargetPricebooks should return the cached list on a second call');

        List<Product2> products = [SELECT Id FROM Product2 WHERE RES_Product_External_ID__c = 'UNIT-600'];
        Assert.areEqual(0, products.size(), 'Unknown layout has no target maps to populate required Product2 Name');

        RES_Product_Staging__c processedRow = [SELECT RES_Processing_Status__c FROM RES_Product_Staging__c WHERE Id = :row.Id];
        Assert.areEqual('Error', processedRow.RES_Processing_Status__c, 'Staging row should be marked Error due to missing Name mapping');

        engine.disqualifyNewProducts(new Map<String, Id>());
    }

    // ==================================================================
    // Direct unit tests of the @TestVisible / public static helper methods.
    // These are independent of org metadata and give deterministic branch coverage.
    // ==================================================================
    @IsTest
    static void testHelperMethods_MergeCoercionLiteralsAndPicklists() {
        // ---- merged() ----
        RES_Product_Staging__c r1 = new RES_Product_Staging__c(RES_Product_Code__c = 'A');
        RES_Product_Staging__c r2 = new RES_Product_Staging__c(RES_Product_Code__c = 'B');
        List<RES_Product_Staging__c> rows = new List<RES_Product_Staging__c>{ r1, r2 };

        Assert.areEqual('A', RES_UnifiedIngestionEngine.merged(rows, 'RES_Product_Code__c', 'First_Non_Null'));
        Assert.areEqual('B', RES_UnifiedIngestionEngine.merged(rows, 'RES_Product_Code__c', 'Last_Non_Null'));
        Assert.isNull(RES_UnifiedIngestionEngine.merged(
            new List<RES_Product_Staging__c>{ new RES_Product_Staging__c() }, 'RES_Product_Code__c', 'First_Non_Null'));
        Assert.isNull(RES_UnifiedIngestionEngine.merged(rows, 'Not_A_Real_Field__c', 'First_Non_Null'));

        // ---- putCoerced(): DATE, DATETIME, INTEGER, STRING (with truncation), BOOLEAN, default ----
        Opportunity opp = new Opportunity();
        RES_UnifiedIngestionEngine.putCoerced(
            opp, Opportunity.CloseDate.getDescribe().getSObjectField(), Datetime.newInstance(2026, 1, 15, 10, 0, 0));
        Assert.areEqual(Date.newInstance(2026, 1, 15), opp.CloseDate, 'Datetime should be coerced to Date');

        Task t = new Task();
        RES_UnifiedIngestionEngine.putCoerced(
            t, Task.ReminderDateTime.getDescribe().getSObjectField(), Date.newInstance(2026, 2, 1));
        Assert.areEqual(Datetime.newInstance(Date.newInstance(2026, 2, 1), Time.newInstance(0, 0, 0, 0)), t.ReminderDateTime,
            'Date should be coerced to midnight Datetime');

        Account acc = new Account();
        RES_UnifiedIngestionEngine.putCoerced(acc, Account.NumberOfEmployees.getDescribe().getSObjectField(), Decimal.valueOf('12.6'));
        Assert.areEqual(13, acc.NumberOfEmployees, 'Decimal should round to nearest Integer (HALF_UP)');

        // ---- putCoerced(): the non-conversion fallback branch on each typed path
        // (value already matches the target's native type, so it is put through as-is) ----
        Opportunity oppDateAlready = new Opportunity();
        RES_UnifiedIngestionEngine.putCoerced(
            oppDateAlready, Opportunity.CloseDate.getDescribe().getSObjectField(), Date.newInstance(2026, 6, 1));
        Assert.areEqual(Date.newInstance(2026, 6, 1), oppDateAlready.CloseDate, 'A Date value for a Date field passes straight through');

        Task taskDatetimeAlready = new Task();
        RES_UnifiedIngestionEngine.putCoerced(
            taskDatetimeAlready, Task.ReminderDateTime.getDescribe().getSObjectField(), Datetime.newInstance(2026, 6, 1, 9, 0, 0));
        Assert.areEqual(Datetime.newInstance(2026, 6, 1, 9, 0, 0), taskDatetimeAlready.ReminderDateTime,
            'A Datetime value for a Datetime field passes straight through');

        Account accIntegerAlready = new Account();
        RES_UnifiedIngestionEngine.putCoerced(
            accIntegerAlready, Account.NumberOfEmployees.getDescribe().getSObjectField(), 42);
        Assert.areEqual(42, accIntegerAlready.NumberOfEmployees, 'An Integer value for an Integer field passes straight through');

        Integer nameLen = Account.Name.getDescribe().getLength();
        String longName = ''.leftPad(nameLen + 50, 'X');
        RES_UnifiedIngestionEngine.putCoerced(acc, Account.Name.getDescribe().getSObjectField(), longName);
        Assert.areEqual(nameLen, acc.Name.length(), 'String should be truncated to the field length');

        Contact c1 = new Contact();
        RES_UnifiedIngestionEngine.putCoerced(c1, Contact.HasOptedOutOfEmail.getDescribe().getSObjectField(), true);
        Assert.areEqual(true, c1.HasOptedOutOfEmail, 'Native Boolean should pass through');

        Contact c2 = new Contact();
        RES_UnifiedIngestionEngine.putCoerced(c2, Contact.HasOptedOutOfEmail.getDescribe().getSObjectField(), 'N');
        Assert.areEqual(false, c2.HasOptedOutOfEmail, '"N" should coerce to false');

        Contact c3 = new Contact();
        RES_UnifiedIngestionEngine.putCoerced(c3, Contact.HasOptedOutOfEmail.getDescribe().getSObjectField(), 'yes');
        Assert.areEqual(true, c3.HasOptedOutOfEmail, 'Any other non-blank string should coerce to true');

        Account acc2 = new Account();
        RES_UnifiedIngestionEngine.putCoerced(acc2, Account.AnnualRevenue.getDescribe().getSObjectField(), Decimal.valueOf('1000.50'));
        Assert.areEqual(1000.50, acc2.AnnualRevenue, 'Currency/Double fields fall into the default branch');

        // ---- putLiteral(): Boolean, Double/Currency, Integer, Picklist, default String ----
        Account acc3 = new Account();
        RES_UnifiedIngestionEngine.putLiteral(acc3, Account.AnnualRevenue.getDescribe().getSObjectField(), '2500.75');
        Assert.areEqual(2500.75, acc3.AnnualRevenue);

        Account acc4 = new Account();
        RES_UnifiedIngestionEngine.putLiteral(acc4, Account.NumberOfEmployees.getDescribe().getSObjectField(), '42');
        Assert.areEqual(42, acc4.NumberOfEmployees);

        Account acc5 = new Account();
        RES_UnifiedIngestionEngine.putLiteral(acc5, Account.Name.getDescribe().getSObjectField(), 'Literal Co');
        Assert.areEqual('Literal Co', acc5.Name);

        Account acc6 = new Account();
        RES_UnifiedIngestionEngine.putLiteral(acc6, Account.NumberOfEmployees.getDescribe().getSObjectField(), 'not-a-number');
        Assert.isNull(acc6.NumberOfEmployees);

        RES_UnifiedIngestionEngine.putLiteral(acc6, Account.Name.getDescribe().getSObjectField(), null);
        Assert.isNull(acc6.Name, 'Null literal should be a no-op');

        // ---- putTemporal(): null, Date target, Datetime target, non-temporal input ----
        Opportunity opp2 = new Opportunity();
        RES_UnifiedIngestionEngine.putTemporal(opp2, Opportunity.CloseDate.getDescribe().getSObjectField(), null);
        Assert.isNull(opp2.CloseDate);

        RES_UnifiedIngestionEngine.putTemporal(
            opp2, Opportunity.CloseDate.getDescribe().getSObjectField(), Datetime.newInstance(2026, 3, 1, 0, 0, 0));
        Assert.areEqual(Date.newInstance(2026, 3, 1), opp2.CloseDate);

        Task t2 = new Task();
        RES_UnifiedIngestionEngine.putTemporal(t2, Task.ReminderDateTime.getDescribe().getSObjectField(), Date.newInstance(2026, 4, 1));
        Assert.isNotNull(t2.ReminderDateTime);

        Opportunity opp3 = new Opportunity();
        RES_UnifiedIngestionEngine.putTemporal(opp3, Opportunity.CloseDate.getDescribe().getSObjectField(), 'not a date');
        Assert.isNull(opp3.CloseDate, 'Non Date/Datetime input should be ignored');

        // ---- safePicklist(): null field, blank raw, non-picklist passthrough, match, no-match, cache hit ----
        Assert.isNull(RES_UnifiedIngestionEngine.safePicklist(null, 'Hot'));
        Assert.isNull(RES_UnifiedIngestionEngine.safePicklist(Account.Rating.getDescribe().getSObjectField(), ''));
        Assert.areEqual('Not a picklist field', RES_UnifiedIngestionEngine.safePicklist(
            Account.Name.getDescribe().getSObjectField(), 'Not a picklist field'));

        String match = RES_UnifiedIngestionEngine.safePicklist(Account.Rating.getDescribe().getSObjectField(), 'hot');
        Assert.areEqual('Hot', match, 'Case-insensitive match against a standard Rating value');
        String matchAgain = RES_UnifiedIngestionEngine.safePicklist(Account.Rating.getDescribe().getSObjectField(), 'HOT');
        Assert.areEqual('Hot', matchAgain);

        Assert.isNull(RES_UnifiedIngestionEngine.safePicklist(
            Account.Rating.getDescribe().getSObjectField(), 'Definitely Not A Real Value'));
    }

    // ==================================================================
    // Batch scaffolding (zero-arg constructor, start(), finish()) plus the
    // remaining pure-logic @TestVisible helpers that don't need any DML:
    // isNewer(), adjustmentFrom()/adjustmentTo(), and resolveAdjustmentSchedule().
    // ==================================================================
    @IsTest
    static void testBatchScaffoldingAndScheduleHelpers() {
        // ---- Zero-arg constructor picks the first active layout; start()/finish() ----
        RES_UnifiedIngestionEngine defaultEngine = new RES_UnifiedIngestionEngine();
        Database.QueryLocator ql = defaultEngine.start(null);
        Assert.isNotNull(ql, 'start() should return a query locator for the pending staging rows');
        defaultEngine.finish(null);

        // ---- isNewer(): null candidate, null current, candidate newer, candidate older ----
        Assert.isFalse(RES_UnifiedIngestionEngine.isNewer(null, Date.today()));
        Assert.isTrue(RES_UnifiedIngestionEngine.isNewer(Date.today(), null));
        Assert.isTrue(RES_UnifiedIngestionEngine.isNewer(Date.today(), Date.today().addDays(-1)));
        Assert.isFalse(RES_UnifiedIngestionEngine.isNewer(Date.today().addDays(-1), Date.today()));

        // ---- adjustmentFrom() / adjustmentTo(): every branch, driven off an in-memory
        // (never inserted) PriceAdjustmentSchedule so no DML is needed ----
        PriceAdjustmentSchedule sch = new PriceAdjustmentSchedule(
            EffectiveFrom = Datetime.newInstanceGmt(Date.newInstance(2020, 1, 1), Time.newInstance(0, 0, 0, 0)),
            EffectiveTo   = Datetime.newInstanceGmt(Date.newInstance(2030, 1, 1), Time.newInstance(0, 0, 0, 0))
        );

        Assert.areEqual(sch.EffectiveFrom.addDays(1), RES_UnifiedIngestionEngine.adjustmentFrom(null, sch),
            'A null row date should fall back to the schedule earliest allowed start');
        Assert.areEqual(sch.EffectiveFrom.addDays(1),
            RES_UnifiedIngestionEngine.adjustmentFrom(Date.newInstance(2019, 1, 1), sch),
            'A row date before the schedule start should clamp to the earliest allowed start');
        Date midFrom = Date.newInstance(2021, 1, 1);
        Assert.areEqual(Datetime.newInstanceGmt(midFrom, Time.newInstance(0, 0, 0, 0)),
            RES_UnifiedIngestionEngine.adjustmentFrom(midFrom, sch),
            'A row date within range should be used as-is');

        Assert.areEqual(sch.EffectiveTo.addDays(-1), RES_UnifiedIngestionEngine.adjustmentTo(null, sch),
            'A null row date should fall back to the schedule latest allowed end');
        Assert.areEqual(sch.EffectiveTo.addDays(-1),
            RES_UnifiedIngestionEngine.adjustmentTo(Date.newInstance(2031, 1, 1), sch),
            'A row date after the schedule end should clamp to the latest allowed end');
        Date midTo = Date.newInstance(2022, 1, 1);
        Assert.areEqual(Datetime.newInstanceGmt(midTo, Time.newInstance(23, 59, 59, 0)),
            RES_UnifiedIngestionEngine.adjustmentTo(midTo, sch),
            'A row date within range should be used as-is');

        PriceAdjustmentSchedule openEnded = new PriceAdjustmentSchedule(EffectiveFrom = sch.EffectiveFrom);
        Assert.isNull(RES_UnifiedIngestionEngine.adjustmentTo(null, openEnded),
            'An open-ended schedule with no row date has no upper bound');

        // ---- resolveAdjustmentSchedule(): blank layout config, and a name that does not exist ----
        RES_UnifiedIngestionEngine engine = new RES_UnifiedIngestionEngine(LAYOUT_CODE);
        RES_IngestionConfig.Layout blankLayout = new RES_IngestionConfig.Layout();
        Assert.isNull(engine.resolveAdjustmentSchedule(blankLayout),
            'A layout naming no schedule should resolve to null');

        RES_IngestionConfig.Layout missingLayout = new RES_IngestionConfig.Layout();
        missingLayout.priceAdjustmentSchedule = 'Definitely Not A Real Schedule';
        Assert.isNull(engine.resolveAdjustmentSchedule(missingLayout),
            'A schedule name that matches no record should resolve to null');
    }
}