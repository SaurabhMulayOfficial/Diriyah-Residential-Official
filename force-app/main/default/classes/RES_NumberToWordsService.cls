public with sharing class RES_NumberToWordsService {
    // ---- English lookups ----
    private static final List<String> EN_ONES = new List<String>{
        '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
        'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
        'Seventeen', 'Eighteen', 'Nineteen'
    };
    private static final List<String> EN_TENS = new List<String>{
        '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
    };
    private static final List<String> EN_SCALES = new List<String>{
        '', 'Thousand', 'Million', 'Billion', 'Trillion'
    };

    // ---- Arabic lookups ----
    private static final List<String> AR_ONES = new List<String>{
        '', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة',
        'عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر', 'ستة عشر',
        'سبعة عشر', 'ثمانية عشر', 'تسعة عشر'
    };
    private static final List<String> AR_TENS = new List<String>{
        '', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'
    };
    private static final List<String> AR_HUNDREDS = new List<String>{
        '', 'مئة', 'مئتان', 'ثلاثمائة', 'أربعمائة', 'خمسمائة', 'ستمائة', 'سبعمائة', 'ثمانمائة', 'تسعمائة'
    };
    // scale forms: {singular, dual, plural(3-10), accusative(11+)}
    private static final Map<Integer, List<String>> AR_SCALES = new Map<Integer, List<String>>{
        1 => new List<String>{ 'ألف', 'ألفان', 'آلاف', 'ألفاً' },
        2 => new List<String>{ 'مليون', 'مليونان', 'ملايين', 'مليوناً' },
        3 => new List<String>{ 'مليار', 'ملياران', 'مليارات', 'ملياراً' },
        4 => new List<String>{ 'تريليون', 'تريليونان', 'تريليونات', 'تريليوناً' }
    };

    // ===================== Invocable =====================
    public class Request {
        @InvocableVariable(label='Amount' description='Numeric amount to spell out')
        public Decimal amount;
    }

    public class Result {
        @InvocableVariable(label='Words (English)')
        public String englishWords;
        @InvocableVariable(label='Words (Arabic)')
        public String arabicWords;
    }

    @InvocableMethod(label='Convert Amount To Words (SAR)' description='Spells a SAR amount in English and Arabic')
    public static List<Result> convert(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }
        for (Request req : requests) {
            Result r = new Result();
            Decimal amount = (req == null) ? null : req.amount;
            r.englishWords = toEnglishWords(amount);
            r.arabicWords = toArabicWords(amount);
            results.add(r);
        }
        return results;
    }

    // Apex List.add(index, element) requires an existing index, so build
    // groups least-significant-first and reverse into most-significant order.
    private static List<String> reverse(List<String> items) {
        List<String> ordered = new List<String>();
        for (Integer i = items.size() - 1; i >= 0; i--) {
            ordered.add(items[i]);
        }
        return ordered;
    }

    // ===================== English =====================
    public static String toEnglishWords(Decimal amount) {
        if (amount == null) {
            return '';
        }
        Long totalHalalas = (amount.setScale(2, System.RoundingMode.HALF_UP) * 100).round();
        Long riyals = totalHalalas / 100;
        Integer halalas = (Integer) Math.mod(totalHalalas, 100);

        String words = enInteger(riyals) + ' Saudi Riyals';
        if (halalas > 0) {
            words += ' And ' + enInteger(halalas) + ' Halalas';
        }
        return words;
    }

    private static String enInteger(Long n) {
        if (n == 0) {
            return 'Zero';
        }
        List<String> parts = new List<String>();
        Integer scaleIdx = 0;
        while (n > 0) {
            Integer grp = (Integer) Math.mod(n, 1000);
            if (grp > 0) {
                String g = enThreeDigits(grp);
                if (scaleIdx > 0) {
                    g += ' ' + EN_SCALES[scaleIdx];
                }
                parts.add(g);
            }
            n = n / 1000;
            scaleIdx++;
        }
        return String.join(reverse(parts), ' ');
    }

    private static String enThreeDigits(Integer n) {
        List<String> out = new List<String>();
        Integer hundreds = n / 100;
        Integer rem = Math.mod(n, 100);
        if (hundreds > 0) {
            out.add(EN_ONES[hundreds] + ' Hundred');
        }
        if (rem > 0) {
            if (rem < 20) {
                out.add(EN_ONES[rem]);
            } else {
                Integer t = rem / 10;
                Integer o = Math.mod(rem, 10);
                out.add(o > 0 ? EN_TENS[t] + '-' + EN_ONES[o] : EN_TENS[t]);
            }
        }
        return String.join(out, ' ');
    }

    // ===================== Arabic =====================
    public static String toArabicWords(Decimal amount) {
        if (amount == null) {
            return '';
        }
        Long totalHalalas = (amount.setScale(2, System.RoundingMode.HALF_UP) * 100).round();
        Long riyals = totalHalalas / 100;
        Integer halalas = (Integer) Math.mod(totalHalalas, 100);

        String words = arInteger(riyals) + ' ريالاً سعودياً';
        if (halalas > 0) {
            words += ' و' + arThreeDigits(halalas) + ' هللة';
        }
        return words;
    }

    private static String arInteger(Long n) {
        if (n == 0) {
            return 'صفر';
        }
        List<String> parts = new List<String>();
        Integer scaleIdx = 0;
        while (n > 0) {
            Integer grp = (Integer) Math.mod(n, 1000);
            if (grp > 0) {
                parts.add(arGroupWithScale(grp, scaleIdx));
            }
            n = n / 1000;
            scaleIdx++;
        }
        return String.join(reverse(parts), ' و');
    }

    private static String arGroupWithScale(Integer grp, Integer scaleIdx) {
        if (scaleIdx == 0) {
            return arThreeDigits(grp);
        }
        List<String> forms = AR_SCALES.get(scaleIdx);
        if (grp == 1) {
            return forms[0]; // ألف
        } else if (grp == 2) {
            return forms[1]; // ألفان
        } else if (grp >= 3 && grp <= 10) {
            return arThreeDigits(grp) + ' ' + forms[2]; // ثلاثة آلاف
        }
        return arThreeDigits(grp) + ' ' + forms[3]; // مئتان وواحد وسبعون ألفاً
    }

    private static String arThreeDigits(Integer n) {
        List<String> out = new List<String>();
        Integer hundreds = n / 100;
        Integer rem = Math.mod(n, 100);
        if (hundreds > 0) {
            out.add(AR_HUNDREDS[hundreds]);
        }
        if (rem > 0) {
            if (rem < 20) {
                out.add(AR_ONES[rem]);
            } else {
                Integer t = rem / 10;
                Integer o = Math.mod(rem, 10);
                out.add(o > 0 ? AR_ONES[o] + ' و' + AR_TENS[t] : AR_TENS[t]);
            }
        }
        return String.join(out, ' و');
    }
}