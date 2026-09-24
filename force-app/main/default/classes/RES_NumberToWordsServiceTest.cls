/**
 * Tests for RES_NumberToWordsService.
 * English assertions are exact. Arabic assertions cover the core cases;
 * extend with native-speaker-validated expected strings as needed.
 */
@IsTest
private class RES_NumberToWordsServiceTest {
    @IsTest
    static void englishMatchesReferenceExample() {
        // The reference value provided by the business.
        String words = RES_NumberToWordsService.toEnglishWords(4271478.54);
        System.assertEquals(
            'Four Million Two Hundred Seventy-One Thousand Four Hundred Seventy-Eight Saudi Riyals And Fifty-Four Halalas',
            words,
            'English wording did not match the reference example'
        );
    }

    @IsTest
    static void englishHandlesWholeAmountsAndZero() {
        System.assertEquals('One Thousand Saudi Riyals', RES_NumberToWordsService.toEnglishWords(1000));
        System.assertEquals('Zero Saudi Riyals', RES_NumberToWordsService.toEnglishWords(0));
        System.assertEquals(
            'One Hundred Saudi Riyals And Fifty Halalas',
            RES_NumberToWordsService.toEnglishWords(100.50)
        );
    }

    @IsTest
    static void englishRoundsToTwoDecimals() {
        // 0.555 -> 0.56
        System.assertEquals(
            'Zero Saudi Riyals And Fifty-Six Halalas',
            RES_NumberToWordsService.toEnglishWords(0.555)
        );
    }

    @IsTest
    static void arabicProducesExpectedShape() {
        String words = RES_NumberToWordsService.toArabicWords(4271478.54);
        System.assert(words.contains('أربعة ملايين'), 'Expected millions phrase: ' + words);
        System.assert(words.contains('ألفاً'), 'Expected thousands phrase: ' + words);
        System.assert(words.contains('ريالاً سعودياً'), 'Expected currency phrase: ' + words);
        System.assert(words.contains('هللة'), 'Expected halala phrase: ' + words);
    }

    @IsTest
    static void invocableReturnsBothLanguages() {
        RES_NumberToWordsService.Request req = new RES_NumberToWordsService.Request();
        req.amount = 4271478.54;

        Test.startTest();
        List<RES_NumberToWordsService.Result> results =
            RES_NumberToWordsService.convert(new List<RES_NumberToWordsService.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(String.isNotBlank(results[0].englishWords), 'English words missing');
        System.assert(String.isNotBlank(results[0].arabicWords), 'Arabic words missing');
    }

    @IsTest
    static void handlesNull() {
        System.assertEquals('', RES_NumberToWordsService.toEnglishWords(null));
        System.assertEquals('', RES_NumberToWordsService.toArabicWords(null));
    }
}