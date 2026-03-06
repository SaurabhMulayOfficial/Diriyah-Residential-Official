/*  
    * This class provides a simple in-memory cache for query results, keyed by a string.
    * It allows for storing and retrieving lists of SObjects based on a cache key, which typically includes the SObject type.
    * The cache can be invalidated for specific SObject types, and it can also be cleared entirely.

    Author: Saurabh Mulay
    Date: 2026-02
*/

public with sharing class RES_QueryCacheProvider {

    private static Map<String, List<SObject>> queryCache = new Map<String, List<SObject>>();
    private static Set<String> invalidatedTypes = new Set<String>();
    
    public static List<SObject> get(String cacheKey) {
        String typeName = getSObjectType(cacheKey);
        
        if (invalidatedTypes.contains(typeName)) {
            queryCache.remove(cacheKey);
            return null;
        }
        
        return queryCache.get(cacheKey);
    }
    
    public static void put(String cacheKey, List<SObject> records) {
        queryCache.put(cacheKey, records);
    }
    
    public static Boolean contains(String cacheKey) {
        return queryCache.containsKey(cacheKey);
    }
    
    public static void invalidate(String sObjectType) {
        invalidatedTypes.add(sObjectType);
    }
    
    public static void clearAll() {
        queryCache.clear();
        invalidatedTypes.clear();
    }
    
    private static String getSObjectType(String cacheKey) {
        return cacheKey.substringBefore('_');
    }
}