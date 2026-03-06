/**
 * ==============================================================================
 * Class Name    : RES_LeadMassConversionUtility
 * Description   : Flow-invocable utility to bulk convert Leads dynamically.
 *                 Accepts a collection of Lead records from a Screen Flow,
 *                 validates ownership, fetches the correct converted status
 *                 via DAO, and performs bulk Lead conversion using
 *                 Database.convertLead().
 * Author        : Rohan Jambhule
 * Company       : Globant Inc
 * Created Date  : Feb 23, 2026
 * Version       : 2.0
 * ==============================================================================
 */
public with sharing class RES_LeadMassConversionUtility {

    private static final String CLASS_NAME = 'RES_LeadMassConversionUtility';

    // =========================================================================
    // Invocable Request Wrapper
    // Received from Flow — contains leads to convert, status label, and
    // a flag to control Opportunity creation during conversion.
    // =========================================================================
    public class ConvertRequest {
        @InvocableVariable(required=true)
        public List<Lead> leads;

        @InvocableVariable(required=true)
        public String convertedStatusLabel;

        @InvocableVariable(required=true)
        public Boolean doNotCreateOpp;
    }

    // =========================================================================
    // Flow Entry Point
    // Invoked by Screen Flow. Orchestrates the full Lead conversion pipeline:
    // validate request → collect IDs → fetch status → fetch leads →
    // validate owners → execute conversion.
    // =========================================================================
    @InvocableMethod(label='Convert Leads Dynamically')
    public static void convertLeads(List<ConvertRequest> requests) {
        if (isInvalidRequest(requests)) {
            return;
        }

        Set<Id> leadIds = collectLeadIds(requests);
        if (leadIds.isEmpty()) {
            return;
        }

        String convertedStatus = fetchConvertedStatus(requests[0].convertedStatusLabel);

        List<Lead> leadsToConvert = fetchLeads(leadIds);
        if (leadsToConvert.isEmpty()) {
            return;
        }

        validateLeadOwners(leadsToConvert);
        executeConversion(leadsToConvert, convertedStatus, requests[0].doNotCreateOpp);
    }

    // =========================================================================
    // Validates the incoming request list.
    // Returns true if the request is null or empty, preventing further
    // execution when no valid input is provided.
    // =========================================================================
    private static Boolean isInvalidRequest(List<ConvertRequest> requests) {
        return (requests == null || requests.isEmpty());
    }

    // =========================================================================
    // Collects unique Lead IDs from all requests in the batch.
    // Uses Map keying to automatically deduplicate IDs across
    // multiple ConvertRequest entries.
    // =========================================================================
    private static Set<Id> collectLeadIds(List<ConvertRequest> requests) {
        List<Lead> allLeads = new List<Lead>();
        for (ConvertRequest req : requests) {
            if (req.leads != null) {
                allLeads.addAll(req.leads);
            }
        }
        return new Map<Id, Lead>(allLeads).keySet();
    }

    // =========================================================================
    // Fetches the ApiName of the converted LeadStatus via DAO layer.
    // Accepts the MasterLabel (e.g. 'Qualified') from the Flow Custom Label
    // and returns the corresponding ApiName (e.g. '04') required by
    // Database.convertLead().
    // Throws AuraHandledException if no matching status is found,
    // which surfaces the error back to the Flow screen.
    // =========================================================================
    private static String fetchConvertedStatus(String statusLabel) {
        String convertedStatus = new RES_LeadDAOLayer().getConvertedStatusLabel(statusLabel);
        if (String.isBlank(convertedStatus)) {
            throw new AuraHandledException(
                'Converted Status "' + statusLabel + '" not found.'
            );
        }
        return convertedStatus;
    }

    // =========================================================================
    // Fetches Lead records from the DAO layer by their IDs.
    // Only returns Leads matching RES_Company or RES_Individual RecordTypes.
    // Returns an empty list if the DAO returns null, preventing null errors
    // in downstream processing.
    // =========================================================================
    private static List<Lead> fetchLeads(Set<Id> leadIds) {
        List<Lead> leads = new RES_LeadDAOLayer().getLeadsById(leadIds);
        return (leads == null) ? new List<Lead>() : leads;
    }

    // =========================================================================
    // Orchestrates the conversion execution.
    // Prepares LeadConvert operations, calls Database.convertLead() in
    // partial-success mode (allOrNone = false), and delegates result
    // handling to handleResults().
    // =========================================================================
    private static void executeConversion(
        List<Lead> leads,
        String convertedStatus,
        Boolean doNotCreateOpp
    ) {
        List<Database.LeadConvert> operations = prepareLeadConvertOperations(
            leads, convertedStatus, doNotCreateOpp
        );

        if (operations.isEmpty()) {
            return;
        }

        List<Database.LeadConvertResult> results = Database.convertLead(operations, false);
        handleResults(results);
    }

    // =========================================================================
    // Builds a list of Database.LeadConvert operations for each Lead.
    // Uses the ApiName from the convertedStatus parameter (supplied by DAO)
    // to set the conversion status — no hardcoding.
    // Retains the Lead's current Owner on the converted records.
    // =========================================================================
    private static List<Database.LeadConvert> prepareLeadConvertOperations(
        List<Lead> leads,
        String convertedStatus,
        Boolean doNotCreateOpp
    ) {
        List<Database.LeadConvert> ops = new List<Database.LeadConvert>();

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

    // =========================================================================
    // Validates that no Lead in the collection is owned by a Queue.
    // Database.convertLead() requires a User as Lead Owner.
    // Throws AuraHandledException listing the affected Lead names,
    // which surfaces the message back to the Flow screen.
    // =========================================================================
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

    // =========================================================================
    // Processes Database.LeadConvert results after conversion.
    // Logs errors for any failed conversions using ERROR log level
    // to aid debugging via Setup → Debug Logs.
    // Runs in partial-success mode — failed leads are logged but do not
    // block successful conversions in the same batch.
    // =========================================================================
    private static void handleResults(List<Database.LeadConvertResult> results) {
        if (results == null || results.isEmpty()) {
            return;
        }

        for (Database.LeadConvertResult r : results) {
            if (!r.isSuccess()) {
                if (r.getErrors() != null && !r.getErrors().isEmpty()) {
                    for (Database.Error err : r.getErrors()) {
                        System.debug(
                            LoggingLevel.ERROR,
                            '[' + CLASS_NAME + '] Conversion Failed | LeadId: ' + r.getLeadId()
                            + ' | Code: '    + err.getStatusCode()
                            + ' | Message: ' + err.getMessage()
                            + ' | Fields: '  + err.getFields()
                        );
                    }
                }
            }
        }
    }
}