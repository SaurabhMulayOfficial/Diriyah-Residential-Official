/**
 * Class Name: RES_HijriDateUtility
 * Description: Utility class that converts a Gregorian Date/Datetime into its
 *              Hijri (Islamic) calendar equivalent using the standard arithmetic
 *              (Kuwaiti) algorithm — the same tabular conversion Java and .NET
 *              use for the Islamic calendar. Apex has no native Hijri support.
 *
 *              Datetime inputs are converted using the running user's local
 *              date (the calendar day the user sees), not the UTC day.
 */
public with sharing class RES_HijriDateUtility {
    private static final Integer HIJRI_EPOCH_JD = 1948440;

    // Hijri month names (index 1-12), used by formatLong().
    private static final List<String> HIJRI_MONTH_NAMES = new List<String>{
        '',
        'Muharram',
        'Safar',
        'Rabi al-Awwal',
        'Rabi al-Thani',
        'Jumada al-Awwal',
        'Jumada al-Thani',
        'Rajab',
        'Shaban',
        'Ramadan',
        'Shawwal',
        'Dhu al-Qadah',
        'Dhu al-Hijjah'
    };

    /**
     * Simple wrapper for a converted Hijri date.
     */
    public class HijriDate {
        public Integer year { get; private set; }
        public Integer month { get; private set; }
        public Integer day { get; private set; }

        public HijriDate(Integer year, Integer month, Integer day) {
            this.year = year;
            this.month = month;
            this.day = day;
        }

        /** ISO-style "1447-02-28" (zero-padded). */
        public override String toString() {
            return year +
                '-' +
                String.valueOf(month).leftPad(2, '0') +
                '-' +
                String.valueOf(day).leftPad(2, '0');
        }

        /** Human-readable "28 Safar 1447 AH". */
        public String formatLong() {
            return day + ' ' + HIJRI_MONTH_NAMES.get(month) + ' ' + year + ' AH';
        }
    }

    /**
     * Flow-invocable input. Provide either gregorianDate or gregorianDateTime
     * (gregorianDate wins when both are supplied).
     */
    public class HijriRequest {
        @InvocableVariable(
            label='Gregorian Date'
            description='Date to convert. Takes priority over Gregorian Datetime.'
        )
        public Date gregorianDate;

        @InvocableVariable(
            label='Gregorian Datetime'
            description='Datetime to convert (uses the running user\'s local day).'
        )
        public Datetime gregorianDateTime;
    }

    /**
     * Flow-invocable output. hijriDateText / hijriDateLong are the values you
     * normally assign to a field; the parts are exposed for further logic.
     */
    public class HijriResult {
        @InvocableVariable(label='Hijri Date (ISO, e.g. 1447-02-28)')
        public String hijriDateText;

        @InvocableVariable(label='Hijri Date (Long, e.g. 28 Safar 1447 AH)')
        public String hijriDateLong;

        @InvocableVariable(label='Hijri Year')
        public Integer hijriYear;

        @InvocableVariable(label='Hijri Month')
        public Integer hijriMonth;

        @InvocableVariable(label='Hijri Day')
        public Integer hijriDay;
    }

    /**
     * Flow entry point. Converts each request's Gregorian Date/Datetime into a
     * Hijri date. Bulk-safe: the returned list is index-aligned with the input.
     *
     * @param requests one HijriRequest per record.
     * @return one HijriResult per request (fields null when no input supplied).
     */
    @InvocableMethod(
        label='Convert to Hijri Date'
        description='Converts a Gregorian Date or Datetime into its Hijri (Islamic) equivalent.'
        category='Diriyah Residential'
    )
    public static List<HijriResult> convertToHijri(List<HijriRequest> requests) {
        List<HijriResult> results = new List<HijriResult>();
        for (HijriRequest request : requests) {
            HijriResult result = new HijriResult();
            HijriDate converted = request.gregorianDate != null
                ? convert(request.gregorianDate)
                : convert(request.gregorianDateTime);
            if (converted != null) {
                result.hijriDateText = converted.toString();
                result.hijriDateLong = converted.formatLong();
                result.hijriYear = converted.year;
                result.hijriMonth = converted.month;
                result.hijriDay = converted.day;
            }
            results.add(result);
        }
        return results;
    }

    /**
     * Converts a Gregorian Date to its Hijri equivalent.
     *
     * @param gregorianDate the Gregorian date to convert.
     * @return the corresponding HijriDate, or null when the input is null.
     */
    public static HijriDate convert(Date gregorianDate) {
        if (gregorianDate == null) {
            return null;
        }
        return fromParts(
            gregorianDate.year(),
            gregorianDate.month(),
            gregorianDate.day()
        );
    }

    /**
     * Converts a Gregorian Datetime to its Hijri equivalent, based on the
     * running user's local calendar day.
     *
     * @param gregorianDateTime the Gregorian datetime to convert.
     * @return the corresponding HijriDate, or null when the input is null.
     */
    public static HijriDate convert(Datetime gregorianDateTime) {
        if (gregorianDateTime == null) {
            return null;
        }
        // date() uses the running user's timezone — the day the user actually sees.
        return convert(gregorianDateTime.date());
    }

    /**
     * Convenience formatter returning the zero-padded ISO Hijri string
     * (e.g. "1447-02-28").
     *
     * @param gregorianDate the Gregorian date to convert.
     * @return the formatted Hijri date, or null when the input is null.
     */
    public static String toHijriString(Date gregorianDate) {
        HijriDate result = convert(gregorianDate);
        return result == null ? null : result.toString();
    }

    /**
     * Convenience formatter returning the zero-padded ISO Hijri string
     * for a Datetime (e.g. "1447-02-28").
     *
     * @param gregorianDateTime the Gregorian datetime to convert.
     * @return the formatted Hijri date, or null when the input is null.
     */
    public static String toHijriString(Datetime gregorianDateTime) {
        HijriDate result = convert(gregorianDateTime);
        return result == null ? null : result.toString();
    }

    /**
     * Core conversion: Gregorian y/m/d -> Hijri via Julian Day Number.
     * Uses Long arithmetic to avoid overflow on the intermediate products.
     */
    private static HijriDate fromParts(
        Integer gYear,
        Integer gMonth,
        Integer gDay
    ) {
        Long jd = gregorianToJulianDay(gYear, gMonth, gDay);

        Long l = jd - HIJRI_EPOCH_JD + 10632;
        Long n = intDiv(l - 1, 10631);
        l = l - 10631 * n + 354;
        Long j =
            intDiv(10985 - l, 5316) * intDiv(50 * l, 17719) +
            intDiv(l, 5670) * intDiv(43 * l, 15238);
        l =
            l -
            intDiv(30 - j, 15) * intDiv(17719 * j, 50) -
            intDiv(j, 16) * intDiv(15238 * j, 43) +
            29;

        Integer hMonth = (Integer) intDiv(24 * l, 709);
        Integer hDay = (Integer) (l - intDiv(709 * hMonth, 24));
        Integer hYear = (Integer) (30 * n + j - 30);

        return new HijriDate(hYear, hMonth, hDay);
    }

    /**
     * Gregorian calendar date to Julian Day Number (Fliegel & Van Flandern).
     */
    private static Long gregorianToJulianDay(
        Integer year,
        Integer month,
        Integer day
    ) {
        Long a = intDiv(month - 14, 12);
        return intDiv(1461 * (year + 4800 + a), 4) +
            intDiv(367 * (month - 2 - 12 * a), 12) -
            intDiv(3 * intDiv(year + 4900 + a, 100), 4) +
            day -
            32075;
    }

    /**
     * Floor integer division. Apex '/' on Long truncates toward zero, which is
     * wrong for negative numerators (e.g. month - 14). This floors instead.
     */
    private static Long intDiv(Long numerator, Long denominator) {
        Long q = numerator / denominator;
        if ((Math.mod(numerator, denominator) != 0) && ((numerator < 0) != (denominator < 0))) {
            q--;
        }
        return q;
    }
}