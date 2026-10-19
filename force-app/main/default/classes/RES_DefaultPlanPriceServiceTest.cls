/** Tests for RES_DefaultPlanPriceService (SeeAllData=true for the org's real ProductRelationshipType and 'Pricing_Option' attribute). */
@isTest(SeeAllData=true)
private class RES_DefaultPlanPriceServiceTest {

    private static final String PRICE_OPTION = 'RES Test Default Plan Premium';

    private static Id unitRecordTypeId;
    private static Id paymentPlanRecordTypeId;

    private static void setUpMocks() {
        RES_IntegrationRequestEventService.batchSubmitter = new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        Map<String, Schema.RecordTypeInfo> infos = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName();
        unitRecordTypeId = infos.get('RES_Residential_Sales').getRecordTypeId();
        paymentPlanRecordTypeId = infos.get('RES_Residential_Payment_Plan').getRecordTypeId();
    }

    private static ProductCatalog createCatalog() {
        RES_Config_Switch__c config = RES_Config_Switch__c.getOrgDefaults();
        Boolean wasOff = config.RES_Triggers_Off__c;
        config.RES_Triggers_Off__c = true;
        upsert config;
        ProductCatalog catalog = new ProductCatalog(Name = 'RES Test Default Plan Catalog');
        insert catalog;
        config.RES_Triggers_Off__c = wasOff;
        upsert config;
        return catalog;
    }

    private static Product2 createUnit(Id catalogId) {
        Product2 unit = new Product2(
            Name = 'RES Test Default Plan Unit', IsActive = false, RecordTypeId = unitRecordTypeId,
            RES_Business_Entity__c = catalogId, Type = 'Bundle', ConfigureDuringSale = 'Allowed'
        );
        insert unit;
        return [SELECT Id, IsActive, RecordTypeId, CurrencyIsoCode, RES_Default_Plan_Price__c FROM Product2 WHERE Id = :unit.Id];
    }

    private static void provision(Id catalogId) {
        Product2 plan = new Product2(
            Name = 'RES Test Default Plan', IsActive = true, RecordTypeId = paymentPlanRecordTypeId,
            RES_Business_Entity__c = catalogId, RES_Price_Option__c = PRICE_OPTION
        );
        insert plan;
        RES_PaymentPlanBundleProvisioner.Request req = new RES_PaymentPlanBundleProvisioner.Request();
        req.paymentPlanId = plan.Id;
        RES_PaymentPlanBundleProvisioner.provision(new List<RES_PaymentPlanBundleProvisioner.Request>{ req });
    }

    /** Override adjustment on the unit for PRICE_OPTION via the org's real 'Pricing_Option' attribute. */
    private static AttributeBasedAdjustment insertAdjustment(Id unitId, Decimal value) {
        PriceAdjustmentSchedule pas = new PriceAdjustmentSchedule(
            Name = 'RES Test Default Plan Schedule', ScheduleType = 'Attribute', AdjustmentMethod = 'Range',
            IsActive = true, EffectiveFrom = DateTime.now()
        );
        insert pas;

        List<AttributeDefinition> existing = [SELECT Id FROM AttributeDefinition WHERE DeveloperName = 'Pricing_Option' LIMIT 1];
        AttributeDefinition pricingOption = existing.isEmpty()
            ? new AttributeDefinition(Name = 'RES Test Pricing Option', Label = 'RES Test Pricing Option', DeveloperName = 'Pricing_Option', DataType = 'Text', IsActive = true)
            : existing[0];
        if (pricingOption.Id == null) {
            insert pricingOption;
        }

        ProductClassification classification = new ProductClassification(
            Code = 'RES_TEST_DPP_CLASS_' + String.valueOf(Crypto.getRandomInteger()).right(8),
            Name = 'RES Test Default Plan Classification', Status = 'Active'
        );
        insert classification;
        insert new ProductClassificationAttr(
            Name = 'RES Test Pricing Option', ProductClassificationId = classification.Id,
            AttributeDefinitionId = pricingOption.Id, IsPriceImpacting = true
        );
        update new Product2(Id = unitId, BasedOnId = classification.Id);

        AttributeBasedAdjRule rule = new AttributeBasedAdjRule(Name = 'RES Test Default Plan Rule');
        insert rule;
        insert new AttributeAdjustmentCondition(
            AttributeBasedAdjRuleId = rule.Id, AttributeDefinitionId = pricingOption.Id,
            ProductId = unitId, Operator = 'equals', StringValue = PRICE_OPTION
        );
        AttributeBasedAdjustment adjustment = new AttributeBasedAdjustment(
            PriceAdjustmentScheduleId = pas.Id, ProductId = unitId, AttributeBasedAdjRuleId = rule.Id,
            AdjustmentType = 'Override', AdjustmentValue = value, EffectiveFrom = DateTime.now()
        );
        insert adjustment;
        return adjustment;
    }

    private static String priceOf(Id unitId) {
        return [SELECT RES_Default_Plan_Price__c FROM Product2 WHERE Id = :unitId].RES_Default_Plan_Price__c;
    }

    @isTest
    static void refreshStampsAndUpdatesDefaultPlanPrice() {
        setUpMocks();
        ProductCatalog catalog = createCatalog();
        Product2 unit = createUnit(catalog.Id);

        Test.startTest();
        provision(catalog.Id);
        AttributeBasedAdjustment adjustment = insertAdjustment(unit.Id, 2500000);
        RES_DefaultPlanPriceService.refresh(new Set<Id>{ unit.Id });
        String initial = priceOf(unit.Id);

        update new AttributeBasedAdjustment(Id = adjustment.Id, AdjustmentValue = 2750000.5);
        RES_DefaultPlanPriceService.refresh(new Set<Id>{ unit.Id });
        Test.stopTest();

        System.assertEquals('2,500,000 ' + unit.CurrencyIsoCode, initial);
        System.assertEquals('2,750,000.50 ' + unit.CurrencyIsoCode, priceOf(unit.Id), 'Price follows the adjustment value');
    }

    @isTest
    static void refreshClearsPriceWhenUnitHasNoDefaultPlan() {
        setUpMocks();
        ProductCatalog catalog = createCatalog();
        Product2 unit = createUnit(catalog.Id);
        update new Product2(Id = unit.Id, RES_Default_Plan_Price__c = 'stale');

        Test.startTest();
        RES_DefaultPlanPriceService.refresh(new Set<Id>{ unit.Id });
        Test.stopTest();

        System.assertEquals(null, priceOf(unit.Id));
    }

    @isTest
    static void applyOnActivationStampsPriceWithoutDml() {
        setUpMocks();
        ProductCatalog catalog = createCatalog();
        Product2 unit = createUnit(catalog.Id);
        provision(catalog.Id);
        insertAdjustment(unit.Id, 1200000);

        Product2 activated = unit.clone(true, true);
        activated.IsActive = true;
        Product2 untouched = unit.clone(true, true);

        Test.startTest();
        RES_DefaultPlanPriceService.applyOnActivation(new List<Product2>{ activated }, new Map<Id, Product2>{ unit.Id => unit });
        RES_DefaultPlanPriceService.applyOnActivation(new List<Product2>{ untouched }, new Map<Id, Product2>{ unit.Id => unit });
        RES_DefaultPlanPriceService.applyOnActivation(new List<Product2>{ activated }, null);
        Test.stopTest();

        System.assertEquals('1,200,000 ' + unit.CurrencyIsoCode, activated.RES_Default_Plan_Price__c);
        System.assertEquals(unit.RES_Default_Plan_Price__c, untouched.RES_Default_Plan_Price__c, 'Only a unit turning Active is stamped');
    }

    @isTest
    static void formatPriceIsLocaleIndependent() {
        System.assertEquals(null, RES_DefaultPlanPriceService.formatPrice(null, 'SAR'));
        System.assertEquals('0 SAR', RES_DefaultPlanPriceService.formatPrice(0, 'SAR'));
        System.assertEquals('950 SAR', RES_DefaultPlanPriceService.formatPrice(950, null));
        System.assertEquals('1,000 SAR', RES_DefaultPlanPriceService.formatPrice(1000, 'SAR'));
        System.assertEquals('12,345,678.90 USD', RES_DefaultPlanPriceService.formatPrice(12345678.9, 'USD'));
        System.assertEquals('-1,500.25 SAR', RES_DefaultPlanPriceService.formatPrice(-1500.249, 'SAR'));
    }
}
