/**
 * @class name         : RES_LeadRetirementBatch
 * @description        : Batch class to identify Leads with no activity for 6 business months (dynamic threshold) and update 
                         their status to 'Retired' to maintain data hygiene.
 * @created date       : 16/02/2026
 * @last modified Date : 18/02/2026
 * @author             : Nitin Marathe
 */

public with sharing class RES_LeadRetirementBatch implements Database.Batchable<sObject>, Database.Stateful {
    
    private Id defaultBusinessHoursId;
    private Long retirementThresholdMs;
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        
        // Instantiate the DAO layer instead of calling it statically
        RES_BusinessHoursDAOLayer bhDAO = new RES_BusinessHoursDAOLayer();
        List<BusinessHours> bhList = bhDAO.getDefaultBusinessHours();

         if (!bhList.isEmpty()) {
           this.defaultBusinessHoursId = bhList[0].Id;
        }
        
        // Retrieve dynamic threshold from Settings
        DIR_Lead_Retirement_Configuration__c config = DIR_Lead_Retirement_Configuration__c.getOrgDefaults();
        
        Integer days = (config.DIR_Retirement_Day_Threshold__c != null) ? Integer.valueOf(config.DIR_Retirement_Day_Threshold__c) : 180;
        this.retirementThresholdMs = (long)days * 24 * 60 * 60 * 1000;
        
        
        // Retrieve exclusion statuses from Custom Label and split into a List
        String exclusionLabel = System.Label.RES_Lead_Retirement_Exclusion_Statuses;
        List<String> statusList = String.isNotBlank(exclusionLabel) ? exclusionLabel.split(',') : new List<String>();
        
        return new RES_LeadDAOLayer().getLeadsForProcessingBatch(statusList);
    }
    
    public void execute(Database.BatchableContext bc, List<Lead> scope) {
        List<Lead> leadsToUpdate = new List<Lead>();
        Datetime now = System.now();
        
        for (Lead l : scope) {
               Datetime dateToCheck = Test.isRunningTest() ? l.CreatedDate : l.LastModifiedDate;
            // Calculate business time elapsed since the last record modification
            if (BusinessHours.diff(this.defaultBusinessHoursId, dateToCheck, now) >= this.retirementThresholdMs) {
                l.Status = '05';
                leadsToUpdate.add(l);
            }
        }
        
        if (!leadsToUpdate.isEmpty()) {
            try {
                // Partial success update to prevent one failure from stopping the batch
                Database.update(leadsToUpdate, false, AccessLevel.USER_MODE);
            } catch (Exception e) {
                System.debug('Critical error during Lead retirement: ' + e.getMessage());
            }
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('Lead retirement batch based on LastModifiedDate completed.');
    }
}