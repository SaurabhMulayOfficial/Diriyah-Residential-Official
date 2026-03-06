/**
 * @class name         : RES_BusinessHoursDAOLayer
 * @description        : DAO Layer class for BusinessHours object to provide centralized 
                         data access and query execution, extending the Base DAO framework.
 * @created date       : 18/02/2026
 * @last modified Date : 18/02/2026
 * @author             : Nitin Marathe
 */

public with sharing class RES_BusinessHoursDAOLayer extends RES_BaseDAOLayer {
    public RES_BusinessHoursDAOLayer() {}

    protected override string getSObjectName(){
        return 'BusinessHours';
    } 
    /*
    * Query has been Utilized in RES_LeadRetirementBatch to fetch Business Hours.
    */

    public List<sObject> getDefaultBusinessHours(){
        String soql = 'SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1';
        List<SObject> results = executeQuery(soql, 'DefaultBusiness', true, null, AccessLevel.SYSTEM_MODE);
        return results;
    }

}