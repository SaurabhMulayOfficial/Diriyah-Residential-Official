/**
 * Class Name: RES_HijriDateUtilityTest
 * Description: Unit tests for RES_HijriDateUtility. Verifies the Gregorian ->
 *              Hijri arithmetic (Kuwaiti algorithm) against fixed checkpoints,
 *              the string/wrapper formatters, null handling, and the Flow-
 *              invocable entry point. Pure logic — no DML or test data needed.
 */
@IsTest
private class RES_HijriDateUtilityTest {
    @IsTest
    static void convertDate_returnsExpectedHijriParts() {
        // Checkpoints computed from the same Kuwaiti algorithm the class uses.
        RES_HijriDateUtility.HijriDate h = RES_HijriDateUtility.convert(
            Date.newInstance(2026, 8, 27)
        );
        System.assertEquals(1448, h.year, 'Hijri year for 2026-08-27');
        System.assertEquals(3, h.month, 'Hijri month for 2026-08-27');
        System.assertEquals(15, h.day, 'Hijri day for 2026-08-27');

        RES_HijriDateUtility.HijriDate h2 = RES_HijriDateUtility.convert(
            Date.newInstance(2000, 1, 1)
        );
        System.assertEquals(1420, h2.year, 'Hijri year for 2000-01-01');
        System.assertEquals(9, h2.month, 'Hijri month for 2000-01-01');
        System.assertEquals(26, h2.day, 'Hijri day for 2000-01-01');

        RES_HijriDateUtility.HijriDate h3 = RES_HijriDateUtility.convert(
            Date.newInstance(1979, 11, 20)
        );
        System.assertEquals(1400, h3.year, 'Hijri year for 1979-11-20');
        System.assertEquals(1, h3.month, 'Hijri month for 1979-11-20');
        System.assertEquals(2, h3.day, 'Hijri day for 1979-11-20');
    }

    @IsTest
    static void toString_isZeroPaddedIso() {
        RES_HijriDateUtility.HijriDate h = RES_HijriDateUtility.convert(
            Date.newInstance(1979, 11, 20)
        );
        // Month and day must be zero-padded so the text sorts chronologically.
        System.assertEquals('1400-01-02', h.toString(), 'Zero-padded ISO output');
    }

    @IsTest
    static void formatLong_usesArabicMonthName() {
        RES_HijriDateUtility.HijriDate h = RES_HijriDateUtility.convert(
            Date.newInstance(2026, 8, 27)
        );
        System.assertEquals(
            '15 Rabi al-Awwal 1448 AH',
            h.formatLong(),
            'Long format with month name'
        );
    }

    @IsTest
    static void toHijriString_dateOverload() {
        System.assertEquals(
            '1445-10-02',
            RES_HijriDateUtility.toHijriString(Date.newInstance(2024, 4, 10)),
            'toHijriString(Date)'
        );
    }

    @IsTest
    static void toHijriString_datetimeOverload_usesLocalDay() {
        // newInstance interprets in the running user's time zone, so .date()
        // is deterministic here regardless of the org's default TZ.
        Datetime dt = Datetime.newInstance(2024, 4, 10, 10, 30, 0);
        System.assertEquals(
            '1445-10-02',
            RES_HijriDateUtility.toHijriString(dt),
            'toHijriString(Datetime)'
        );
    }

    @IsTest
    static void nullInputs_returnNull() {
        Date nullDate = null;
        Datetime nullDatetime = null;
        System.assertEquals(null, RES_HijriDateUtility.convert(nullDate), 'convert(null Date)');
        System.assertEquals(null, RES_HijriDateUtility.convert(nullDatetime), 'convert(null Datetime)');
        System.assertEquals(null, RES_HijriDateUtility.toHijriString(nullDate), 'toHijriString(null Date)');
        System.assertEquals(null, RES_HijriDateUtility.toHijriString(nullDatetime), 'toHijriString(null Datetime)');
    }

    @IsTest
    static void invocable_convertsDateInput() {
        RES_HijriDateUtility.HijriRequest req = new RES_HijriDateUtility.HijriRequest();
        req.gregorianDate = Date.newInstance(1990, 1, 15);

        Test.startTest();
        List<RES_HijriDateUtility.HijriResult> results = RES_HijriDateUtility.convertToHijri(
            new List<RES_HijriDateUtility.HijriRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result per request');
        RES_HijriDateUtility.HijriResult r = results[0];
        System.assertEquals('1410-06-19', r.hijriDateText, 'ISO text output');
        System.assertEquals(1410, r.hijriYear, 'Year part');
        System.assertEquals(6, r.hijriMonth, 'Month part');
        System.assertEquals(19, r.hijriDay, 'Day part');
        System.assertEquals('19 Jumada al-Thani 1410 AH', r.hijriDateLong, 'Long output');
    }

    @IsTest
    static void invocable_dateWinsOverDatetime() {
        RES_HijriDateUtility.HijriRequest req = new RES_HijriDateUtility.HijriRequest();
        req.gregorianDate = Date.newInstance(2024, 4, 10);
        // A different datetime that must be ignored because gregorianDate is set.
        req.gregorianDateTime = Datetime.newInstance(2000, 1, 1, 0, 0, 0);

        List<RES_HijriDateUtility.HijriResult> results = RES_HijriDateUtility.convertToHijri(
            new List<RES_HijriDateUtility.HijriRequest>{ req }
        );
        System.assertEquals('1445-10-02', results[0].hijriDateText, 'Date input takes priority');
    }

    @IsTest
    static void invocable_datetimeFallbackAndEmptyRequest() {
        RES_HijriDateUtility.HijriRequest withDatetime = new RES_HijriDateUtility.HijriRequest();
        withDatetime.gregorianDateTime = Datetime.newInstance(2024, 4, 10, 9, 0, 0);
        RES_HijriDateUtility.HijriRequest empty = new RES_HijriDateUtility.HijriRequest();

        List<RES_HijriDateUtility.HijriResult> results = RES_HijriDateUtility.convertToHijri(
            new List<RES_HijriDateUtility.HijriRequest>{ withDatetime, empty }
        );

        System.assertEquals(2, results.size(), 'Result list is index-aligned with input');
        System.assertEquals('1445-10-02', results[0].hijriDateText, 'Datetime fallback used');
        System.assertEquals(null, results[1].hijriDateText, 'Empty request yields null fields');
    }
}