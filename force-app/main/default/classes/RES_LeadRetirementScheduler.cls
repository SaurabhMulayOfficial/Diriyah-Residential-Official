/**
 * @class name         : RES_LeadRetirementScheduler
 * @description        : Schedulable wrapper class used to automate the RES_LeadRetirementBatch nightly.
 * @created date       : 16/02/2026
 * @last modified Date : 18/02/2026
 * @author             : Nitin Marathe
 */

public with sharing class RES_LeadRetirementScheduler implements Schedulable {
    
    public void execute(SchedulableContext sc) {
        // Instantiate the batch class
        RES_LeadRetirementBatch batchJob = new RES_LeadRetirementBatch();
        
        // Access Custom Label directly (No SOQL required)
        String labelValue = System.Label.RES_LeadRetirementBatch_Size;
        
        // Convert to Integer with a safe default of 200
        Integer batchSize = String.isNotBlank(labelValue) && labelValue.isNumeric() 
                            ? Integer.valueOf(labelValue) 
                            : 200;
        
        // Execute the batch with a standard size of 200
        Database.executeBatch(batchJob, batchSize);
    }
}