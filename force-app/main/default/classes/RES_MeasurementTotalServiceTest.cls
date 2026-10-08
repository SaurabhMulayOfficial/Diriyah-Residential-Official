/**
 * @description Tests for RES_MeasurementTotalService: total measurements calculated from active components and kept out of SAP sync.
 *              Product setup runs with triggers switched off so only the measurement path is under test.
 */
@IsTest
private class RES_MeasurementTotalServiceTest {

    private static Product2 createProduct(String name) {
        RES_Config_Switch__c cfg = RES_Config_Switch__c.getOrgDefaults();
        cfg.RES_Triggers_Off__c = true;
        upsert cfg;
        Product2 p = new Product2(Name = name, ProductCode = name);
        insert p;
        cfg.RES_Triggers_Off__c = false;
        upsert cfg;
        return p;
    }

    private static RES_Measurement__c build(Id productId, String type, Decimal amount, String uom, Date fromDate, Date toDate) {
        return new RES_Measurement__c(
            Name = type, RES_Product__c = productId, RES_Measurement_Type__c = type, RES_Measurement_Amount__c = amount,
            RES_Unit_Of_Measurement__c = uom, RES_Measurement_From__c = fromDate, RES_Measurement_To__c = toDate
        );
    }

    /** Active total amount per total type for the product. */
    private static Map<String, Decimal> activeTotals(Id productId) {
        Map<String, Decimal> result = new Map<String, Decimal>();
        Set<String> totalTypes = RES_MeasurementTotalService.getTotalTypes();
        for (RES_Measurement__c m : [
            SELECT RES_Measurement_Type__c, RES_Measurement_Amount__c FROM RES_Measurement__c
            WHERE RES_Product__c = :productId AND RES_Active__c = true AND RES_Measurement_Type__c IN :totalTypes
        ]) {
            System.assert(!result.containsKey(m.RES_Measurement_Type__c), 'Only one active record per total type');
            result.put(m.RES_Measurement_Type__c, m.RES_Measurement_Amount__c);
        }
        return result;
    }

    @IsTest
    static void totalsAreCalculatedThroughTheWholeTree() {
        Product2 p = createProduct('T1');
        Date today = RES_ProductMeasurementSyncService.today();
        Test.startTest();
        insert new List<RES_Measurement__c>{
            build(p.Id, 'Y011', 100, 'Sqr Mtr', today.addDays(-5), null),
            build(p.Id, 'Y012', 50.25, 'Sqr Mtr', today.addDays(-2), today.addDays(30)),
            build(p.Id, 'Y021', 30, 'Sqr Mtr', today, null)
        };
        Test.stopTest();

        Map<String, Decimal> totals = activeTotals(p.Id);
        System.assertEquals(150.25, totals.get('Y020'));
        System.assertEquals(30, totals.get('Y030'));
        System.assertEquals(150.25, totals.get('Y035'));
        System.assertEquals(180.25, totals.get('Y040'));
        System.assertEquals(180.25, totals.get('Y055'));
        System.assert(!totals.containsKey('M007'), 'No parking component, so no parking total');

        RES_Measurement__c y020 = [SELECT RES_Unit_Of_Measurement__c, RES_Measurement_From__c, RES_Measurement_To__c, Name
                                   FROM RES_Measurement__c WHERE RES_Product__c = :p.Id AND RES_Measurement_Type__c = 'Y020'];
        System.assertEquals('Sqr Mtr', y020.RES_Unit_Of_Measurement__c);
        System.assertEquals(today.addDays(-2), y020.RES_Measurement_From__c, 'Latest component From');
        System.assertEquals(today.addDays(30), y020.RES_Measurement_To__c, 'Earliest component To');
        System.assertEquals('Total Internal Area', y020.Name);
    }

    @IsTest
    static void missingComponentCountsAsZero() {
        Product2 p = createProduct('T2');
        Test.startTest();
        insert new List<RES_Measurement__c>{
            build(p.Id, 'M005', 2, 'Pcs', RES_ProductMeasurementSyncService.today(), null),
            build(p.Id, 'Y016', null, 'Sqr Mtr', RES_ProductMeasurementSyncService.today(), null)
        };
        Test.stopTest();
        Map<String, Decimal> totals = activeTotals(p.Id);
        System.assertEquals(2, totals.get('M007'));
        System.assertEquals(0, totals.get('Y020'));
    }

    @IsTest
    static void inactiveComponentsAreNotSummed() {
        Product2 p = createProduct('T3');
        Date today = RES_ProductMeasurementSyncService.today();
        Test.startTest();
        insert new List<RES_Measurement__c>{
            build(p.Id, 'Y011', 100, 'Sqr Mtr', today.addDays(-30), null),
            build(p.Id, 'Y011', 120, 'Sqr Mtr', today.addDays(-1), null),
            build(p.Id, 'Y012', 999, 'Sqr Mtr', today.addDays(1), null),
            build(p.Id, 'Y013', 999, 'Sqr Mtr', today.addDays(-10), today.addDays(-1))
        };
        Test.stopTest();
        System.assertEquals(120, activeTotals(p.Id).get('Y020'), 'Only the active Y011; future and expired are ignored');
    }

    @IsTest
    static void totalsFollowComponentChanges() {
        Product2 p = createProduct('T4');
        RES_Measurement__c y011 = build(p.Id, 'Y011', 100, 'Sqr Mtr', RES_ProductMeasurementSyncService.today(), null);
        insert y011;
        System.assertEquals(100, activeTotals(p.Id).get('Y055'));

        y011.RES_Measurement_Amount__c = 140;
        update y011;
        System.assertEquals(140, activeTotals(p.Id).get('Y055'));

        delete y011;
        System.assert(activeTotals(p.Id).isEmpty(), 'No active component deactivates the totals');
        System.assertEquals(4, [SELECT COUNT() FROM RES_Measurement__c WHERE RES_Product__c = :p.Id], 'Totals Y020/Y035/Y040/Y055 are kept, not deleted');

        undelete y011;
        System.assertEquals(140, activeTotals(p.Id).get('Y055'));
        System.assertEquals(5, [SELECT COUNT() FROM RES_Measurement__c WHERE RES_Product__c = :p.Id], 'Existing totals are reused');
    }

    @IsTest
    static void manualTotalEditIsRecalculated() {
        Product2 p = createProduct('T5');
        insert build(p.Id, 'Y021', 40, 'Sqr Mtr', RES_ProductMeasurementSyncService.today(), null);
        RES_Measurement__c y030 = [SELECT Id FROM RES_Measurement__c WHERE RES_Product__c = :p.Id AND RES_Measurement_Type__c = 'Y030'];
        y030.RES_Measurement_Amount__c = 1;
        update y030;
        System.assertEquals(40, activeTotals(p.Id).get('Y030'));
    }

    @IsTest
    static void bulkComponentsAcrossProducts() {
        RES_Config_Switch__c cfg = RES_Config_Switch__c.getOrgDefaults();
        cfg.RES_Triggers_Off__c = true;
        upsert cfg;
        List<Product2> products = new List<Product2>();
        for (Integer i = 0; i < 20; i++) {
            products.add(new Product2(Name = 'B' + i, ProductCode = 'B' + i));
        }
        insert products;
        cfg.RES_Triggers_Off__c = false;
        upsert cfg;
        RES_IntegrationRequestEventService.batchSubmitter = new RES_IntegrationRequestEventService.CountingBatchSubmitter();

        List<RES_Measurement__c> rows = new List<RES_Measurement__c>();
        for (Product2 p : products) {
            for (String type : new List<String>{ 'Y011', 'Y012', 'Y013', 'Y014', 'Y015', 'Y016', 'Y021', 'Y022', 'M005', 'M006' }) {
                rows.add(build(p.Id, type, 10, type.startsWith('M') ? 'Pcs' : 'Sqr Mtr', RES_ProductMeasurementSyncService.today(), null));
            }
        }
        Test.startTest();
        insert rows;
        Test.stopTest();

        Map<String, Decimal> totals = activeTotals(products[19].Id);
        System.assertEquals(60, totals.get('Y020'));
        System.assertEquals(20, totals.get('Y030'));
        System.assertEquals(80, totals.get('Y055'));
        System.assertEquals(20, totals.get('M007'));
    }

    @IsTest
    static void totalsAreNotSentToSap() {
        RES_Config_Switch__c cfg = RES_Config_Switch__c.getOrgDefaults();
        cfg.RES_Triggers_Off__c = true;
        upsert cfg;
        Product2 p = new Product2(Name = 'T7', ProductCode = 'T7', RES_Product_External_ID__c = '1000/140/99999998');
        insert p;
        ProductCategory cat = RES_IntegrationTestDataFactory.createCategories(1, true)[0];
        RES_Measurement__c leaf = build(p.Id, 'Y011', 10, 'Sqr Mtr', RES_ProductMeasurementSyncService.today(), null);
        RES_Measurement__c total = build(p.Id, 'Y020', 10, 'Sqr Mtr', RES_ProductMeasurementSyncService.today(), null);
        leaf.RES_Category__c = cat.Id;
        total.RES_Category__c = cat.Id;
        insert new List<RES_Measurement__c>{ leaf, total };
        cfg.RES_Triggers_Off__c = false;
        upsert cfg;

        RES_IntegrationTestDataFactory.primeSapToken();
        Test.setMock(HttpCalloutMock.class, new RES_IntegrationTestDataFactory.EndpointRoutingMock());
        RES_IntegrationRequestEventService.CountingBatchSubmitter spy = new RES_IntegrationRequestEventService.CountingBatchSubmitter();
        RES_IntegrationRequestEventService.batchSubmitter = spy;

        Test.startTest();
        Test.getEventBus().deliver();
        RES_MeasurementServices.syncMeasurements(new List<RES_Measurement__c>{ total }, null);
        Test.getEventBus().deliver();
        Integer afterTotal = spy.callCount;
        RES_MeasurementServices.syncMeasurements(new List<RES_Measurement__c>{ leaf }, null);
        Test.stopTest();

        System.assertEquals(0, afterTotal, 'A total measurement must not publish any SAP integration request');
        System.assert(spy.callCount > 0, 'A component measurement still publishes its SAP integration request');
    }

    @IsTest
    static void totalTypesComeFromActiveRules() {
        RES_MeasurementTotalService.rules = new List<RES_Measurement_Total_Rule__mdt>{
            new RES_Measurement_Total_Rule__mdt(RES_Component_Type__c = 'Y011', RES_Total_Type__c = 'Y020', RES_Active__c = true),
            new RES_Measurement_Total_Rule__mdt(RES_Component_Type__c = 'Y021', RES_Total_Type__c = 'Y030', RES_Active__c = false)
        };
        System.assert(RES_MeasurementTotalService.isTotalType('Y020'));
        System.assert(!RES_MeasurementTotalService.isTotalType('Y030'), 'Inactive rule is ignored');
        System.assert(!RES_MeasurementTotalService.isTotalType('Y011'));
        System.assert(!RES_MeasurementTotalService.isTotalType(null));
    }

    @IsTest
    static void circularRuleDoesNotLoop() {
        RES_MeasurementTotalService.rules = new List<RES_Measurement_Total_Rule__mdt>{
            new RES_Measurement_Total_Rule__mdt(RES_Component_Type__c = 'Y011', RES_Total_Type__c = 'Y020', RES_Active__c = true),
            new RES_Measurement_Total_Rule__mdt(RES_Component_Type__c = 'Y020', RES_Total_Type__c = 'Y040', RES_Active__c = true),
            new RES_Measurement_Total_Rule__mdt(RES_Component_Type__c = 'Y040', RES_Total_Type__c = 'Y020', RES_Active__c = true)
        };
        Product2 p = createProduct('T6');
        Test.startTest();
        insert build(p.Id, 'Y011', 10, 'Sqr Mtr', RES_ProductMeasurementSyncService.today(), null);
        Test.stopTest();
        System.assertEquals(10, activeTotals(p.Id).get('Y020'));
    }
}
