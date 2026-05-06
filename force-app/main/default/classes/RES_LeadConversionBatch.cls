/**
 * @class name         : RES_LeadConversionBatch
 * @description        : Batch class to Convert Qualified Leads 
 * @created date       : 28/04/2026
 * @last modified Date : 05/05/2026
 * @author             : Poonam Jain
 */

public with sharing class RES_LeadConversionBatch implements Database.Batchable<sObject>, Database.Stateful {
 
    public Database.QueryLocator start(Database.BatchableContext bc) {
          return new RES_LeadDAOLayer().getQualifiedLeadsForBatch();
    }
    
    public void execute(Database.BatchableContext bc, List<Lead> scope) {
         if (!scope.isEmpty()) {        
        List<Database.LeadConvert> convertList = new List<Database.LeadConvert>();
        
        for (Lead l : scope) {
            
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(l.Id);
            lc.setConvertedStatus('04');
            lc.setDoNotCreateOpportunity(false);
            
            if (l.RecordType.developerName == 'RES_Individual') {
                // Individual Lead
                lc.setOpportunityName(l.Name);
                // Person Account name auto = Lead Name
                
            } else {
                // Company Lead
                lc.setOpportunityName(l.Company);
                // Account name auto = Lead Company
                lc.setContactId(null); // Salesforce auto-creates contact from Lead Name
            }
            
            convertList.add(lc);
        }
        
        if (!convertList.isEmpty()) {
            List<Database.LeadConvertResult> results = Database.convertLead(convertList, false);
            
            for (Database.LeadConvertResult res : results) {
                if (!res.isSuccess()) {
                    System.debug('Conversion failed: ' + res.getErrors()[0].getMessage());
                }
            }
        }
   
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('Lead Conversion batch completed.');
    }
    


}