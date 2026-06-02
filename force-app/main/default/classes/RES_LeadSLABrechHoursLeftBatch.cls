/**
* @class name         : RES_LeadSLABrechHoursLeftBatch
* @description        : Schedulable class used to calculate the time remaining in SLA Breach.
* @created date       : 28/05/2026
* @last modified Date : 28/05/2026
* @author             : Poonam Jain
*/

global class RES_LeadSLABrechHoursLeftBatch implements Database.Batchable<SObject>, Schedulable {
    
    // Start Method
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return new RES_LeadDAOLayer().getNewLeadsForBatch();
    }
    
    // Execute Method
    global void execute(Database.BatchableContext bc, List<Lead> scope) {
        
        if (!scope.isEmpty()) {
            // Get Default Business Hours
            BusinessHours bh = (BusinessHours) new RES_BusinessHoursDAOLayer()
                .getDefaultBusinessHours()[0];
            
            List<Lead> leadsToUpdate = new List<Lead>();
            for (Lead ld : scope) {
                
                // Calculate milliseconds difference
                Long ms = BusinessHours.diff(
                    bh.Id,
                    Datetime.now(),
                    ld.RES_SLA_Due_Time__c
                );
                
                // Convert milliseconds to hours
                Decimal hoursRemaining = ms / (1000.0 * 60 * 60);
             
                 //update custom field
                 ld.RES_SLA_Hours_Remaining__c = hoursRemaining;
                
                 leadsToUpdate.add(ld);
            }
        
        //updating records
         if (!leadsToUpdate.isEmpty()) {
           Database.update(leadsToUpdate, false);
          }
        
      }
    }
    
    // Finish Method
    global void finish(Database.BatchableContext bc) {
        System.debug('Lead SLA Hours Left Calculation Batch Completed');
    }
    
    // Scheduler Method
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new RES_LeadSLABrechHoursLeftBatch(), 200);
    }
}