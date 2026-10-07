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

    private static Map<String, Boolean> activeByName(Id productId) {
        Map<String, Boolean> result = new Map<String, Boolean>();
        for (RES_Measurement__c m : [SELECT Name, RES_Active__c FROM RES_Measurement__c WHERE RES_Product__c = :productId]) {
            result.put(m.Name, m.RES_Active__c);
        }
        return result;
    }

    private static RES_Measurement__c named(RES_Measurement__c m, String name) {
        m.Name = name;
        return m;
    }

    @IsTest
    static void onlyOneActivePerProductAndTypeLatestFromWins() {
        Product2 p = createProduct('A1');
        Date today = RES_ProductMeasurementSyncService.today();
        Test.startTest();
        insert new List<RES_Measurement__c>{
            named(build(p.Id, BUA, 100, 'Sqr Mtr', today.addDays(-30), null), 'old'),
            named(build(p.Id, BUA, 150, 'Sqr Mtr', today.addDays(-2), null), 'newest'),
            named(build(p.Id, BUA, 120, 'Sqr Mtr', today.addDays(-10), null), 'middle'),
            named(build(p.Id, PLOT, 300, 'Sqr Mtr', today.addDays(-1), null), 'plot')
        };
        Test.stopTest();
        Map<String, Boolean> a = activeByName(p.Id);
        System.assertEquals(false, a.get('old'));
        System.assertEquals(true, a.get('newest'));
        System.assertEquals(false, a.get('middle'));
        System.assertEquals(true, a.get('plot'), 'Each type has its own Active record');
    }

    @IsTest
    static void outOfWindowRecordsAreNotActive() {
        Product2 p = createProduct('A2');
        Date today = RES_ProductMeasurementSyncService.today();
        Test.startTest();
        insert new List<RES_Measurement__c>{
            named(build(p.Id, BUA, 1, 'Sqr Mtr', today.addDays(1), null), 'future'),
            named(build(p.Id, PLOT, 2, 'Sqr Mtr', today.addDays(-9), today.addDays(-1)), 'expired')
        };
        Test.stopTest();
        Map<String, Boolean> a = activeByName(p.Id);
        System.assertEquals(false, a.get('future'));
        System.assertEquals(false, a.get('expired'));
    }

    @IsTest
    static void activeFlagMovesWhenDatesChange() {
        Product2 p = createProduct('A3');
        Date today = RES_ProductMeasurementSyncService.today();
        RES_Measurement__c first = named(build(p.Id, BUA, 100, 'Sqr Mtr', today.addDays(-10), null), 'first');
        RES_Measurement__c second = named(build(p.Id, BUA, 200, 'Sqr Mtr', today.addDays(-1), null), 'second');
        insert new List<RES_Measurement__c>{ first, second };
        System.assertEquals(true, activeByName(p.Id).get('second'));

        second.RES_Measurement_To__c = today.addDays(-1); // second expires -> first takes over
        update second;
        Map<String, Boolean> a = activeByName(p.Id);
        System.assertEquals(true, a.get('first'));
        System.assertEquals(false, a.get('second'));
        System.assertEquals('100 Sqr Mtr', reload(p.Id).RES_Build_up_area__c);

        delete first; // nothing left in effect
        System.assertEquals(null, reload(p.Id).RES_Build_up_area__c);
    }

    @IsTest
    static void undatedLatestCreatedIsActiveAndDatedBeatsUndated() {
        Product2 p = createProduct('A4');
        Date today = RES_ProductMeasurementSyncService.today();
        RES_Measurement__c older = named(build(p.Id, ROOMS, 5, 'Pcs', null, null), 'older');
        RES_Measurement__c newer = named(build(p.Id, ROOMS, 9, 'Pcs', null, null), 'newer');
        insert new List<RES_Measurement__c>{ older, newer };
        Test.setCreatedDate(older.Id, Datetime.now().addDays(-5));
        Test.setCreatedDate(newer.Id, Datetime.now().addDays(-1));
        RES_ProductMeasurementSyncService.syncProducts(new Set<Id>{ p.Id });
        Map<String, Boolean> a = activeByName(p.Id);
        System.assertEquals(true, a.get('newer'));
        System.assertEquals(false, a.get('older'));
        System.assertEquals(9, reload(p.Id).RES_No_of_Bedrooms__c);

        insert named(build(p.Id, ROOMS, 6, 'Pcs', today, null), 'dated');
        a = activeByName(p.Id);
        System.assertEquals(true, a.get('dated'), 'A dated in-range record outranks undated ones');
        System.assertEquals(false, a.get('newer'));
        System.assertEquals(6, reload(p.Id).RES_No_of_Bedrooms__c);
    }

    @IsTest
    static void untrackedTypeGetsActiveFlagButProductIsUntouched() {
        Product2 p = createProduct('A5');
        Test.startTest();
        insert named(build(p.Id, 'Z004', 2, 'Pcs', null, null), 'parking');
        Test.stopTest();
        System.assertEquals(true, activeByName(p.Id).get('parking'));
        System.assertEquals(null, reload(p.Id).RES_No_of_Bedrooms__c);
    }

    @IsTest
    static void fullSyncBatchBackfillsActiveFlag() {
        Product2 p = createProduct('A6');
        RES_Measurement__c m = named(build(p.Id, PLOT, 500, 'Sqr Mtr', null, null), 'plot');
        insert m;
        update new RES_Measurement__c(Id = m.Id, RES_Active__c = false); // simulate pre-existing record
        Test.startTest();
        Database.executeBatch(new RES_ProductMeasurementSyncBatch(true));
        Test.stopTest();
        System.assertEquals(true, activeByName(p.Id).get('plot'));
    }

    // ------------------------------------------------------------------
    // Scenario matrix (effective start = From start-of-day, or created moment when From is blank)
    // ------------------------------------------------------------------

    /** Name of the single Active record of the type for the product, or null when none is Active. */
    private static String activeName(Id productId, String type) {
        List<RES_Measurement__c> rows = [SELECT Name FROM RES_Measurement__c
                                         WHERE RES_Product__c = :productId AND RES_Measurement_Type__c = :type AND RES_Active__c = true];
        System.assert(rows.size() <= 1, 'At most one Active record per product and type');
        return rows.isEmpty() ? null : rows[0].Name;
    }

    private static void setCreated(RES_Measurement__c m, Datetime created) {
        Test.setCreatedDate(m.Id, created);
    }

    private static void resync(Id productId) {
        RES_ProductMeasurementSyncService.syncProducts(new Set<Id>{ productId });
    }

    @IsTest
    static void scenarioUndatedRecordCreatedAfterDatedFromWins() { // #7
        Product2 p = createProduct('S7');
        Date today = RES_ProductMeasurementSyncService.today();
        RES_Measurement__c dated = named(build(p.Id, ROOMS, 6, 'Pcs', today.addDays(-5), null), 'dated');
        RES_Measurement__c undated = named(build(p.Id, ROOMS, 9, 'Pcs', null, null), 'undated');
        insert new List<RES_Measurement__c>{ dated, undated };
        setCreated(dated, Datetime.now().addDays(-6));
        setCreated(undated, Datetime.now().addDays(-1));
        resync(p.Id);
        System.assertEquals('undated', activeName(p.Id, ROOMS));
        System.assertEquals(9, reload(p.Id).RES_No_of_Bedrooms__c);
    }

    @IsTest
    static void scenarioDatedFromTodayVersusUndatedCreatedToday() { // #8
        Product2 p = createProduct('S8');
        Date today = RES_ProductMeasurementSyncService.today();
        RES_Measurement__c dated = named(build(p.Id, ROOMS, 6, 'Pcs', today, null), 'dated');
        RES_Measurement__c undated = named(build(p.Id, ROOMS, 9, 'Pcs', null, null), 'undated');
        insert new List<RES_Measurement__c>{ dated, undated };
        setCreated(dated, Datetime.now().addDays(-3));
        setCreated(undated, Datetime.now()); // created today, after the start of today
        resync(p.Id);
        System.assertEquals('undated', activeName(p.Id, ROOMS));
    }

    @IsTest
    static void scenarioDatedFromTodayVersusUndatedCreatedBeforeToday() { // #9
        Product2 p = createProduct('S9');
        Date today = RES_ProductMeasurementSyncService.today();
        RES_Measurement__c dated = named(build(p.Id, ROOMS, 6, 'Pcs', today, null), 'dated');
        RES_Measurement__c undated = named(build(p.Id, ROOMS, 9, 'Pcs', null, null), 'undated');
        insert new List<RES_Measurement__c>{ dated, undated };
        setCreated(undated, Datetime.now().addDays(-2));
        resync(p.Id);
        System.assertEquals('dated', activeName(p.Id, ROOMS));
        System.assertEquals(6, reload(p.Id).RES_No_of_Bedrooms__c);
    }

    @IsTest
    static void scenarioUndatedCreatedBeforeDatedFromLoses() { // #10
        Product2 p = createProduct('S10');
        Date today = RES_ProductMeasurementSyncService.today();
        RES_Measurement__c dated = named(build(p.Id, ROOMS, 6, 'Pcs', today.addDays(-2), null), 'dated');
        RES_Measurement__c undated = named(build(p.Id, ROOMS, 9, 'Pcs', null, null), 'undated');
        insert new List<RES_Measurement__c>{ dated, undated };
        setCreated(undated, Datetime.now().addDays(-10));
        resync(p.Id);
        System.assertEquals('dated', activeName(p.Id, ROOMS));
    }

    @IsTest
    static void scenarioTwoDatedLatestFromThenLatestCreated() { // #11
        Product2 p = createProduct('S11');
        Date today = RES_ProductMeasurementSyncService.today();
        RES_Measurement__c a = named(build(p.Id, PLOT, 1, 'Sqr Mtr', today.addDays(-5), null), 'a');
        RES_Measurement__c b = named(build(p.Id, PLOT, 2, 'Sqr Mtr', today.addDays(-5), null), 'b');
        RES_Measurement__c c = named(build(p.Id, PLOT, 3, 'Sqr Mtr', today.addDays(-9), null), 'c');
        insert new List<RES_Measurement__c>{ a, b, c };
        setCreated(a, Datetime.now().addDays(-8));
        setCreated(b, Datetime.now().addDays(-7));
        setCreated(c, Datetime.now().addDays(-1));
        resync(p.Id);
        System.assertEquals('b', activeName(p.Id, PLOT), 'Same From: latest created; older From loses even if created later');
    }

    @IsTest
    static void scenarioExpiredDatedLetsUndatedWinAndViceVersa() { // #12 and #13
        Product2 p = createProduct('S12');
        Date today = RES_ProductMeasurementSyncService.today();
        RES_Measurement__c expiredDated = named(build(p.Id, BUA, 100, 'Sqr Mtr', today.addDays(-9), today.addDays(-1)), 'expiredDated');
        RES_Measurement__c undated = named(build(p.Id, BUA, 200, 'Sqr Mtr', null, null), 'undated');
        insert new List<RES_Measurement__c>{ expiredDated, undated };
        setCreated(undated, Datetime.now().addDays(-30));
        resync(p.Id);
        System.assertEquals('undated', activeName(p.Id, BUA));

        Product2 q = createProduct('S13');
        RES_Measurement__c expiredUndated = named(build(q.Id, BUA, 100, 'Sqr Mtr', null, today.addDays(-1)), 'expiredUndated');
        RES_Measurement__c dated = named(build(q.Id, BUA, 200, 'Sqr Mtr', today.addDays(-2), null), 'dated');
        insert new List<RES_Measurement__c>{ expiredUndated, dated };
        setCreated(expiredUndated, Datetime.now().addDays(-1));
        resync(q.Id);
        System.assertEquals('dated', activeName(q.Id, BUA));
    }

    @IsTest
    static void scenarioFutureFromWaitsThenTakesOver() { // #14
        Product2 p = createProduct('S14');
        Date today = RES_ProductMeasurementSyncService.today();
        RES_Measurement__c undated = named(build(p.Id, BUA, 100, 'Sqr Mtr', null, null), 'undated');
        RES_Measurement__c future = named(build(p.Id, BUA, 200, 'Sqr Mtr', today.addDays(3), null), 'future');
        insert new List<RES_Measurement__c>{ undated, future };
        setCreated(undated, Datetime.now().addDays(-5));
        resync(p.Id);
        System.assertEquals('undated', activeName(p.Id, BUA), 'Future-dated record is not in window yet');
        System.assertEquals('100 Sqr Mtr', reload(p.Id).RES_Build_up_area__c);

        future.RES_Measurement_From__c = today; // the From date arrives
        update future;
        System.assertEquals('future', activeName(p.Id, BUA));
        System.assertEquals('200 Sqr Mtr', reload(p.Id).RES_Build_up_area__c);
    }

    @IsTest
    static void scenarioNothingInWindowClearsEverything() { // #3, #4, #15
        Product2 p = createProduct('S15');
        Date today = RES_ProductMeasurementSyncService.today();
        insert new List<RES_Measurement__c>{
            named(build(p.Id, BUA, 1, 'Sqr Mtr', today.addDays(2), null), 'future'),
            named(build(p.Id, BUA, 2, 'Sqr Mtr', today.addDays(-9), today.addDays(-3)), 'expired')
        };
        System.assertEquals(null, activeName(p.Id, BUA));
        System.assertEquals(null, reload(p.Id).RES_Build_up_area__c);
    }

    @IsTest
    static void scenarioAddingFromDateToUndatedRecordChangesItsRank() { // #16
        Product2 p = createProduct('S16');
        Date today = RES_ProductMeasurementSyncService.today();
        RES_Measurement__c first = named(build(p.Id, PLOT, 1, 'Sqr Mtr', null, null), 'first');
        RES_Measurement__c second = named(build(p.Id, PLOT, 2, 'Sqr Mtr', null, null), 'second');
        insert new List<RES_Measurement__c>{ first, second };
        setCreated(first, Datetime.now().addDays(-10));
        setCreated(second, Datetime.now().addDays(-5));
        resync(p.Id);
        System.assertEquals('second', activeName(p.Id, PLOT));

        first.RES_Measurement_From__c = today; // starts today -> later than second's creation
        update first;
        System.assertEquals('first', activeName(p.Id, PLOT));
    }
}
