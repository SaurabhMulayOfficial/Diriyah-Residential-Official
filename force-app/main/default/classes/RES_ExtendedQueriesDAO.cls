public without sharing class RES_ExtendedQueriesDAO extends RES_BaseDAOLayer {

    protected override String getSObjectName() {
        return 'RES_Extended_Queries__mdt';
    }

    public List<String> getExtendedQueriesByName(String queryName) {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('queryName', queryName);
        String soql = 'SELECT Fields__c, DeveloperName FROM RES_Extended_Queries__mdt WHERE DeveloperName = :queryName';
        List<RES_Extended_Queries__mdt> mdt = executeQuery(soql, 'getExtendedQueriesByName', true, bindVars, AccessLevel.SYSTEM_MODE);
        List<String> fieldList = new List<String>();
        if(mdt != null){
            String fieldSet = mdt[0].Fields__c;
            if(String.isNotBlank(fieldSet)){
                fieldList = fieldSet.split(',');
            }
        }
        return fieldList;
    }

}