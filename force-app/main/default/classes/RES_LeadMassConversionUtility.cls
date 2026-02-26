/**
 * ==============================================================================
 * Class Name    : RES_LeadConversionsUtility
 * Description   : Flow-invocable utility to bulk convert Leads dynamically
 *                 (no status filter; converts all passed Leads)
 * Author        : Rohan Jambhule
 * Company       : Globant Inc
 * Created Date  : Feb 23, 2026
 * Version       : 1.1
 * Note          : all Leads in collection are converted
 * ==============================================================================
 */
public with sharing class RES_LeadMassConversionUtility {
    /**
     * Inner class to encapsulate conversion parameters for each Flow execution
     */
    public class ConvertRequest {
        /**
         * Your Flow record-collection of Lead records
         */
        @InvocableVariable(label='Leads to Convert'
                          description='Flow record-collection of Lead records'
                          required=true)
        public List<Lead> leads;
        /**
         * The picklist value on LeadStatus (IsConverted = true) to mark as converted
         */
        @InvocableVariable(label='Converted Status Label'
                          description='The picklist value on LeadStatus to mark converted'
                          required=true)
        public String convertedStatusLabel;
        /**
         * Check to suppress Opportunity creation (true = no Opportunity)
         */
        @InvocableVariable(label='Do Not Create Opportunity'
                          description='Check to suppress opportunity creation'
                          required=true)
        public Boolean doNotCreateOpp;
    }
    /**
     * Invocable entry point for Flow to convert Leads dynamically.
     * @param requests List of ConvertRequest instances from Flow
     * @throws AuraHandledException if the specified convertedStatusLabel is not found
     */
    @InvocableMethod(label='Convert Leads Dynamically'
                   description='Converts all provided Leads without status checking.')
    public static void convertLeads(List<ConvertRequest> requests) {
        // Accumulate all Lead IDs into one list, then extract unique IDs
        List<Lead> allLeads = new List<Lead>();
        for (ConvertRequest req : requests) {
            if (req.leads != null) {
                allLeads.addAll(req.leads);
            }
        }
        Set<Id> leadIds = new Map<Id, Lead>(allLeads).keySet();
        // Exit if no Lead IDs provided
        if (leadIds.isEmpty()) {
            return;
        }
        // Dynamically retrieve the converted-status picklist value
        String convertedStatus = new RES_LeadDAOLayer().getConvertedStatusLabel(requests[0].convertedStatusLabel);
        if (String.isBlank(convertedStatus)) {
            throw new AuraHandledException(
                'Converted Status "' + requests[0].convertedStatusLabel + '" not found.'
            );
        }
        List<Lead> toConvert = new RES_LeadDAOLayer().getLeadsById(leadIds);
        // Exit if no matching Leads
        if (toConvert == null || toConvert.isEmpty()) {
            return;
        }
        // Prepare LeadConvert operations
        List<Database.LeadConvert> ops = new List<Database.LeadConvert>();
        for (Lead l : toConvert) {
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(l.Id);
            lc.setConvertedStatus(convertedStatus);
            lc.setDoNotCreateOpportunity(requests[0].doNotCreateOpp);
            ops.add(lc);
        }
        // Execute conversions (partial successes allowed)
        List<Database.LeadConvertResult> results =
            Database.convertLead(ops, /* allOrNone */ false);
        // Log errors for any failed conversions
        for (Database.LeadConvertResult r : results) {
            if (!r.isSuccess()) {
                System.debug(LoggingLevel.ERROR,'Failed converting ' + r.getLeadId() + ': ' + r.getErrors()[0].getMessage());
            }
        }
    }
}