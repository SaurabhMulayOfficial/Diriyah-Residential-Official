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
    private static final String CLASS_NAME = 'RES_LeadMassConversionUtility';
    /*
     * ============================================================
     * Invocable Request Wrapper
     * ============================================================
     */
    public class ConvertRequest {
        @InvocableVariable(required=true)
        public List<Lead> leads;
        @InvocableVariable(required=true)
        public String convertedStatusLabel;
        @InvocableVariable(required=true)
        public Boolean doNotCreateOpp;
    }
    /*
     * ============================================================
     * Flow Entry Point
     * ============================================================
     */
    @InvocableMethod(label='Convert Leads Dynamically')
    public static void convertLeads(List<ConvertRequest> requests) {
        if (isInvalidRequest(requests)) {
            return;
        }
        Set<Id> leadIds = collectLeadIds(requests);
        if (leadIds.isEmpty()) {
            return;
        }
        String convertedStatus =
            fetchConvertedStatus(requests[0].convertedStatusLabel);
        List<Lead> leadsToConvert =
            fetchLeads(leadIds);
        if (leadsToConvert.isEmpty()) {
            return;
        }
        validateLeadOwners(leadsToConvert); 
        executeConversion(
            leadsToConvert,
            convertedStatus,
            requests[0].doNotCreateOpp
        );
    }

    /*
     * ============================================================
     * Validation
     * ============================================================
     */
    private static Boolean isInvalidRequest(
        List<ConvertRequest> requests
    ) {
        return (requests == null || requests.isEmpty());
    }

    /*
     * ============================================================
     * Collect Lead Ids
     * ============================================================
     */
    private static Set<Id> collectLeadIds(
        List<ConvertRequest> requests
    ) {
        List<Lead> allLeads = new List<Lead>();
        for (ConvertRequest req : requests) {
            if (req.leads != null) {
                allLeads.addAll(req.leads);
            }
        }
        return new Map<Id, Lead>(allLeads).keySet();
    }

    /*
     * ============================================================
     * Fetch Converted Status
     * ============================================================
     */
    private static String fetchConvertedStatus(
        String statusLabel
    ) {
        String convertedStatus = new RES_LeadDAOLayer().getConvertedStatusLabel(statusLabel);
        if (String.isBlank(convertedStatus)) {
            throw new AuraHandledException(
                'Converted Status "' + statusLabel + '" not found.'
            );
        }
        return convertedStatus;
    }

    /*
     * ============================================================
     * Fetch Leads From DAO
     * ============================================================
     */
    private static List<Lead> fetchLeads(Set<Id> leadIds) {
        List<Lead> leads = new RES_LeadDAOLayer().getLeadsById(leadIds);
        return (leads == null)? new List<Lead>(): leads;
    }

    /*
     * ============================================================
     * Execute Conversion
     * ============================================================
     */
    private static void executeConversion(List<Lead> leads,String convertedStatus,Boolean doNotCreateOpp) {
        List<Database.LeadConvert> operations =prepareLeadConvertOperations(leads,convertedStatus,doNotCreateOpp);
        if (operations.isEmpty()) {
            return;
        }
        List<Database.LeadConvertResult> results =
            Database.convertLead(operations, false);
        handleResults(results);
    }

    /*
     * ============================================================
     * Prepare LeadConvert Operations
     * ============================================================
     */
    private static List<Database.LeadConvert>
        prepareLeadConvertOperations(
            List<Lead> leads,
            String convertedStatus,
            Boolean doNotCreateOpp
        ) {
        List<Database.LeadConvert> ops =new List<Database.LeadConvert>();
        for (Lead l : leads) {
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(l.Id);
            lc.setConvertedStatus(convertedStatus);
            lc.setDoNotCreateOpportunity(doNotCreateOpp);
            lc.setOwnerId(l.OwnerId);
            ops.add(lc);
        }
        return ops;
    }
    /*
    * ============================================================
    * Validate Lead Owners (No Queue Allowed)
    * ============================================================
    */
    private static void validateLeadOwners(List<Lead> leads) {
        List<String> queueOwnedLeadNames = new List<String>();
        for (Lead l : leads) {
            if (l.OwnerId != null &&
                l.OwnerId.getSObjectType() == Group.SObjectType) {
                queueOwnedLeadNames.add(l.Name);
            }
        }
        if (!queueOwnedLeadNames.isEmpty()) {
            throw new AuraHandledException(
                'In order to convert lead(s), please assign a User as Owner. ' +
                'Currently assigned to Queue for Lead(s): ' +
                String.join(queueOwnedLeadNames, ', ')
            );
        }
    }
    /*
     * ============================================================
     * Handle Conversion Results Safely
     * ============================================================
     */
    private static void handleResults(List<Database.LeadConvertResult> results) {
        if (results == null || results.isEmpty()) {
            return;
        }
        for (Database.LeadConvertResult r : results) {
            if (!r.isSuccess()) {
                if (r.getErrors() != null &&
                    !r.getErrors().isEmpty()) {
                    for (Database.Error err : r.getErrors()) {
                        System.debug(
                            LoggingLevel.ERROR,
                            '['+CLASS_NAME+'] Conversion Failed: '
                            + err.getMessage()
                        );
                    }
                }
            }
        }
    }
}