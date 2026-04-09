/*
Abstract base class for DAO layers, providing common caching logic and query execution.
Note: Subclasses should implement the getSObjectName method to specify the SObject they are working with.

Author: Saurabh Mulay
Date: 2026-02

*/

public abstract class RES_BaseDAOLayer {


    public RES_BaseDAOLayer() {}

    protected abstract String getSObjectName();


    protected List<SObject> executeQuery(String soql, String cacheSuffix, Boolean useCache, Map<String,Object> bindVars, AccessLevel AccessLevel) {

        String cacheKey = buildCacheKey(cacheSuffix);

        if (useCache) {
            List<SObject> cachedResult = RES_QueryCacheProvider.get(cacheKey);
            if (cachedResult != null) {
                return cachedResult;
            }
        }

        List<SObject> records = new List<SObject>();
        
        if(bindVars != null && !bindVars.isEmpty()){
            try{
                records = Database.queryWithBinds(soql, bindVars, AccessLevel);
            } catch (Exception e) {
                System.debug('Error executing query with binds: ' + e.getMessage());
                throw new RES_DAOException('Error executing query with binds: ' + '  '+ soql + ' ' + e.getMessage());
            }
        }
        else{
            try{
                records = Database.query(soql, AccessLevel);
            } catch (Exception e) {
                System.debug('Error executing query: ' + e.getMessage());
                throw new RES_DAOException('Error executing query: ' + '  '+ soql + ' ' + e.getMessage());
            }
        }
        
        if (useCache) {
            RES_QueryCacheProvider.put(cacheKey, records);
        }

        return records;
    }

    protected Map<Id, SObject> executeQueryToMap(String soql, String cacheSuffix, Boolean useCache, Map<String,Object> bindVars, AccessLevel AccessLevel) {
        List<SObject> records = executeQuery(soql, cacheSuffix, useCache, bindVars, AccessLevel);
        Map<Id, SObject> recordMap = new Map<Id, SObject>();
        for (SObject record : records) {
            recordMap.put(record.Id, record);
        }
        return recordMap;
    }

    protected Database.QueryLocator executeBatchQuery(String soql,  Map<String,Object> bindVars, AccessLevel AccessLevel){
        try{
            if(bindVars != null && !bindVars.isEmpty()){
                return Database.getQueryLocatorWithBinds(soql, bindVars, AccessLevel);
            }
            else{
                return Database.getQueryLocator(soql, AccessLevel);
            }

        }
        catch(Exception e){
            System.debug('Error executing batch query with binds: ' + e.getMessage());
            throw new RES_DAOException('Error executing batch Query: ' + '  '+ soql + ' ' + e.getMessage());
        }
    }

    public void invalidateCache() {
        RES_QueryCacheProvider.invalidate(getSObjectName());
    }

    private String buildCacheKey(String suffix) {
        return getSObjectName() + '_' + suffix;
    }
}