/**
 * @description Tests for DIR-1797: active measurement values are copied onto Product2.
 *              Product setup runs with triggers switched off so only the measurement path is under test.
 */
@IsTest
private class RES_ProductMeasurementSyncTest {

    private static final String BUA = 'Z006';
    private static final String NSA = 'Z007';
    private static final String ROOMS = 'Z008';
    private static final String PLOT = 'Z009';
    private static final String INTERNAL = 'Z013';

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
            RES_Product__c = productId, RES_Measurement_Type__c = type, RES_Measurement_Amount__c = amount,
            RES_Unit_Of_Measurement__c = uom, RES_Measurement_From__c = fromDate, RES_Measurement_To__c = toDate
        );
    }

    private static Product2 reload(Id productId) {
        return [SELECT RES_Build_up_area__c, RES_Unit_Total_Area__c, RES_Unit_Plot_Area__c,
                       RES_Internal_unit_Area__c, RES_No_of_Bedrooms__c FROM Product2 WHERE Id = :productId];
    }

    @IsTest
    static void insertActiveMeasurementsPopulatesAllFields() {
        Product2 p = createProduct('P1');
        Date today = RES_ProductMeasurementSyncService.today();
        Test.startTest();
        insert new List<RES_Measurement__c>{
            build(p.Id, BUA, 1041.6800, 'Sqr Mtr', today, null),
            build(p.Id, NSA, 907.0300, 'Sqr Mtr', today.addDays(-5), today.addDays(30)),
            build(p.Id, PLOT, 2999.1300, 'Sqr Mtr', today, today),
            build(p.Id, INTERNAL, 691.4600, 'Sqr Mtr', null, null),
            build(p.Id, ROOMS, 5.0000, 'Pcs', today, null)
        };
        Test.stopTest();

        Product2 r = reload(p.Id);
        System.assertEquals('1041.68 Sqr Mtr', r.RES_Build_up_area__c);
        System.assertEquals('907.03 Sqr Mtr', r.RES_Unit_Total_Area__c);
        System.assertEquals('2999.13 Sqr Mtr', r.RES_Unit_Plot_Area__c);
        System.assertEquals('691.46 Sqr Mtr', r.RES_Internal_unit_Area__c);
        System.assertEquals(5, r.RES_No_of_Bedrooms__c);
    }

    @IsTest
    static void bedroomDecimalsAreRemoved() {
        Product2 p = createProduct('P2');
        Test.startTest();
        insert build(p.Id, ROOMS, 3.7500, 'Pcs', RES_ProductMeasurementSyncService.today(), null);
        Test.stopTest();
        System.assertEquals(3, reload(p.Id).RES_No_of_Bedrooms__c);
    }

    @IsTest
    static void futureAndExpiredMeasurementsAreIgnored() {
        Product2 p = createProduct('P3');
        Date today = RES_ProductMeasurementSyncService.today();
        Test.startTest();
        insert new List<RES_Measurement__c>{
            build(p.Id, BUA, 100, 'Sqr Mtr', today.addDays(1), null),
            build(p.Id, PLOT, 200, 'Sqr Mtr', today.addDays(-10), today.addDays(-1))
        };
        Test.stopTest();
        Product2 r = reload(p.Id);
        System.assertEquals(null, r.RES_Build_up_area__c);
        System.assertEquals(null, r.RES_Unit_Plot_Area__c);
    }

    @IsTest
    static void latestFromDateWinsWhenSeveralAreActive() {
        Product2 p = createProduct('P4');
        Date today = RES_ProductMeasurementSyncService.today();
        Test.startTest();
        insert new List<RES_Measurement__c>{
            build(p.Id, BUA, 100, 'Sqr Mtr', today.addDays(-30), null),
            build(p.Id, BUA, 150, 'Sqr Mtr', today.addDays(-2), null),
            build(p.Id, BUA, 120, 'Sqr Mtr', today.addDays(-10), null)
        };
        Test.stopTest();
        System.assertEquals('150 Sqr Mtr', reload(p.Id).RES_Build_up_area__c);
    }

    @IsTest
    static void updateDeleteAndUndeleteKeepProductInSync() {
        Product2 p = createProduct('P5');
        RES_Measurement__c m = build(p.Id, BUA, 100, 'Sqr Mtr', RES_ProductMeasurementSyncService.today(), null);
        insert m;
        System.assertEquals('100 Sqr Mtr', reload(p.Id).RES_Build_up_area__c);

        m.RES_Measurement_Amount__c = 250.5;
        update m;
        System.assertEquals('250.5 Sqr Mtr', reload(p.Id).RES_Build_up_area__c);

        m.RES_Measurement_To__c = RES_ProductMeasurementSyncService.today().addDays(-1);
        update m;
        System.assertEquals(null, reload(p.Id).RES_Build_up_area__c, 'Expired by edit clears the field');

        m.RES_Measurement_To__c = null;
        update m;
        System.assertEquals('250.5 Sqr Mtr', reload(p.Id).RES_Build_up_area__c);

        delete m;
        System.assertEquals(null, reload(p.Id).RES_Build_up_area__c);

        undelete m;
        System.assertEquals('250.5 Sqr Mtr', reload(p.Id).RES_Build_up_area__c);
    }

    @IsTest
    static void reparentingResyncsOldAndNewProduct() {
        Product2 a = createProduct('PA');
        Product2 b = createProduct('PB');
        RES_Measurement__c m = build(a.Id, PLOT, 300, 'Sqr Mtr', RES_ProductMeasurementSyncService.today(), null);
        insert m;
        m.RES_Product__c = b.Id;
        update m;
        System.assertEquals(null, reload(a.Id).RES_Unit_Plot_Area__c);
        System.assertEquals('300 Sqr Mtr', reload(b.Id).RES_Unit_Plot_Area__c);
    }

    @IsTest
    static void untrackedTypeLeavesProductUntouched() {
        Product2 p = createProduct('P6');
        Test.startTest();
        insert build(p.Id, 'Z004', 2, 'Pcs', RES_ProductMeasurementSyncService.today(), null);
        Test.stopTest();
        Product2 r = reload(p.Id);
        System.assertEquals(null, r.RES_Build_up_area__c);
        System.assertEquals(null, r.RES_No_of_Bedrooms__c);
    }

    @IsTest
    static void batchPicksUpDateBoundaryChanges() {
        Product2 p = createProduct('P7');
        RES_Measurement__c m = build(p.Id, BUA, 100, 'Sqr Mtr', RES_ProductMeasurementSyncService.today().addDays(-10), RES_ProductMeasurementSyncService.today().addDays(5));
        insert m;
        System.assertEquals('100 Sqr Mtr', reload(p.Id).RES_Build_up_area__c);

        // Simulate the To date passing with no save-triggered sync: switch triggers off, edit, switch on
        RES_Config_Switch__c cfg = RES_Config_Switch__c.getOrgDefaults();
        cfg.RES_Triggers_Off__c = true;
        upsert cfg;
        m.RES_Measurement_To__c = RES_ProductMeasurementSyncService.today().addDays(-1);
        update m;
        cfg.RES_Triggers_Off__c = false;
        upsert cfg;
        System.assertEquals('100 Sqr Mtr', reload(p.Id).RES_Build_up_area__c, 'Stale until the batch runs');

        Test.startTest();
        Database.executeBatch(new RES_ProductMeasurementSyncBatch());
        Test.stopTest();
        System.assertEquals(null, reload(p.Id).RES_Build_up_area__c);
    }

    @IsTest
    static void schedulableQueuesBatch() {
        Test.startTest();
        String jobId = System.schedule('RES Product Measurement Sync Test', '0 10 0 * * ?', new RES_ProductMeasurementSyncBatch());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }

    @IsTest
    static void invocableLaunchesBatch() {
        Test.startTest();
        RES_ProductMeasurementSyncInvocable.runBatch();
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'RES_ProductMeasurementSyncBatch' AND JobType = 'BatchApex']);
    }

    @IsTest
    static void noDatesMostRecentlyCreatedWins() {
        Product2 p = createProduct('P8');
        RES_Measurement__c older = build(p.Id, BUA, 100, 'Sqr Mtr', null, null);
        RES_Measurement__c newer = build(p.Id, BUA, 200, 'Sqr Mtr', null, null);
        insert new List<RES_Measurement__c>{ older, newer };
        Test.setCreatedDate(older.Id, Datetime.now().addDays(-5));
        Test.setCreatedDate(newer.Id, Datetime.now().addDays(-1));
        RES_ProductMeasurementSyncService.syncProducts(new Set<Id>{ p.Id });
        System.assertEquals('200 Sqr Mtr', reload(p.Id).RES_Build_up_area__c);

        Test.setCreatedDate(older.Id, Datetime.now().addHours(-1)); // now the other one is the most recent
        RES_ProductMeasurementSyncService.syncProducts(new Set<Id>{ p.Id });
        System.assertEquals('100 Sqr Mtr', reload(p.Id).RES_Build_up_area__c);
    }

    @IsTest
    static void fullSyncBatchBackfillsProductsWithoutDateBoundaries() {
        Product2 p = createProduct('P9');
        insert build(p.Id, PLOT, 500, 'Sqr Mtr', null, null);
        // Wipe the value without a measurement change, then backfill
        update new Product2(Id = p.Id, RES_Unit_Plot_Area__c = null);
        Test.startTest();
        Database.executeBatch(new RES_ProductMeasurementSyncBatch(true));
        Test.stopTest();
        System.assertEquals('500 Sqr Mtr', reload(p.Id).RES_Unit_Plot_Area__c);
    }
}
