@IsTest
private class RES_QueryCacheProviderTest {

    @IsTest
    static void testQueryCacheProvider_AllInOne() {

        RES_QueryCacheProvider.clearAll();
		RecordType t = [SELECT ID from RecordType WHERE DeveloperName = 'RES_Company' AND SobjectType = 'Account' LIMIT 1];
        Account acc = new Account(Name = 'Test Account', RecordTypeID = t.Id);
        insert acc;

        String cacheKey = 'Account_testQuery';
        List<SObject> records = new List<SObject>{ acc };
        RES_QueryCacheProvider.put(cacheKey, records);

        System.assert(
            RES_QueryCacheProvider.contains(cacheKey),
            'Cache should contain key after put.'
        );

        List<SObject> cachedRecords = RES_QueryCacheProvider.get(cacheKey);

        System.assertNotEquals(null, cachedRecords, 'Cached records should not be null.');
        System.assertEquals(1, cachedRecords.size(), 'Cached list size should match.');
        System.assertEquals(acc.Id, cachedRecords[0].Id, 'Cached record should match inserted record.');
        RES_QueryCacheProvider.invalidate('Account');

        List<SObject> afterInvalidate = RES_QueryCacheProvider.get(cacheKey);

        System.assertEquals(
            null,
            afterInvalidate,
            'Cache should return null after invalidation.'
        );

        System.assert(
            !RES_QueryCacheProvider.contains(cacheKey),
            'Cache key should be removed after invalidation.'
        );

        RES_QueryCacheProvider.put(cacheKey, records);

        System.assert(
            RES_QueryCacheProvider.contains(cacheKey),
            'Cache should allow re-put even after invalidation.'
        );

        RES_QueryCacheProvider.clearAll();

        System.assert(
            !RES_QueryCacheProvider.contains(cacheKey),
            'Cache should be empty after clearAll.'
        );

        RES_QueryCacheProvider.put(cacheKey, records);
        List<SObject> afterClear = RES_QueryCacheProvider.get(cacheKey);

        System.assertNotEquals(
            null,
            afterClear,
            'Cache should work normally after clearAll reset.'
        );
    }
}