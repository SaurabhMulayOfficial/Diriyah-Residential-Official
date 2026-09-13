/*
 * Class Name  : RES_AsyncApexJobDAOLayer
 * Description : DAO layer for AsyncApexJob object.
 */
public without sharing class RES_AsyncApexJobDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'AsyncApexJob';
    }

    public List<AsyncApexJob> getJobById(Id jobId) {
        if (jobId == null) return new List<AsyncApexJob>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'jobId' => jobId };
        String soql = 'SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors, ExtendedStatus ' +
                      'FROM AsyncApexJob WHERE Id = :jobId LIMIT 1';
        return (List<AsyncApexJob>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}