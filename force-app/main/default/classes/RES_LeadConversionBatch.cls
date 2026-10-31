/**
 * @class name         : RES_LeadConversionBatch
 * @description        : Batch class to Convert Qualified Leads 
 * @created date       : 28/04/2026
 * @last modified Date : 21/09/2026
 * @author             : Poonam Jain
 */

public with sharing class RES_LeadConversionBatch implements Database.Batchable<sObject>, Database.Stateful {

    private Set<Id> leadIds;

    public RES_LeadConversionBatch() {}

    // Converts only the given leads (still must be Qualified, unconverted, RES_Company/RES_Individual)
    public RES_LeadConversionBatch(Set<Id> leadIds) {
        this.leadIds = leadIds;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
          RES_LeadDAOLayer dao = new RES_LeadDAOLayer();
          return leadIds == null ? dao.getQualifiedLeadsForBatch() : dao.getQualifiedLeadsForBatch(leadIds);
    }
    
    public void execute(Database.BatchableContext bc, List<Lead> scope) {
         if (!scope.isEmpty()) {        
        String convertedStatus = new RES_LeadDAOLayer().getConvertedStatusLabel('Converted');
        List<Database.LeadConvert> convertList = new List<Database.LeadConvert>();

        for (Lead l : scope) {
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(l.Id);
            lc.setConvertedStatus(convertedStatus);
            lc.setDoNotCreateOpportunity(false);

            if (l.RecordType.developerName == 'RES_Individual') {
                lc.setOpportunityName(l.Name);
            } else {
                lc.setOpportunityName(l.Company);
            }

            convertList.add(lc);
        }

        if (!convertList.isEmpty()) {
            List<Database.LeadConvertResult> results = Database.convertLead(convertList, false, AccessLevel.USER_MODE);
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