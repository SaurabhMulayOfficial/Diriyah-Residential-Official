/**
 * DIR-869 / DIR-1612: Replaces the RES_Customer_Approved_Quote_Locked validation rule.
 *
 * Once a Quote (Residential Sales record type) has been Customer Approved, no field may be
 * changed except the explicit allow-list below, or a transition of Status to 'Cancelled'.
 *
 * Unlike the validation rule it replaces (which only blocked the save when NONE of a short list
 * of fields had changed - meaning a single allow-listed field change would let any other field
 * change ride along unblocked in the same save), this walks every field on the record and blocks
 * on the first non-exempt field that actually differs. That is what "not allowed to be modified
 * except the fields below" means literally, and it is safe to unit test.
 */
public without sharing class RES_QuoteCustomerApprovedLockHandler {

    private static final String LOCKED_RECORD_TYPE = 'RES_Residential_Sales';
    private static final String LOCKED_STATUS = 'Customer Approved';
    private static final String CANCELLED_STATUS = 'Cancelled';

    private static final String ERROR_MESSAGE = 'This quote has been Customer Approved and is locked. It can no longer be edited, except to cancel it.';

    // Fields the business has explicitly allowed to keep changing on a Customer Approved quote.
    // NOTE: Schema.SObjectType.X.fields.getMap() keys are always lower-cased, so these must be too.
    @TestVisible
    private static final Set<String> EXEMPT_FIELDS = new Set<String>{
        'issyncing',
        'res_extend_soft_hold_by_hours__c',
        'res_unit_blocked_end_date__c',
        'res_approval_request_remarks__c',
        'res_reservation_start_date__c',       // stamped by RES_OpportunityStageUpdateValidation on Reservation
        'contractid',                          // stamped by RES_OpportunityStageUpdateValidation on Reservation
        'res_product_soft_held__c',            // cleared by RES_Product_After_Insert_Update_Product_Management_Flow
        'res_unit_blocked_start_date__c'       // cleared by RES_Product_After_Insert_Update_Product_Management_Flow
    };

    // Fields Salesforce itself mutates on every save regardless of what the user/process touched.
    private static final Set<String> SYSTEM_FIELDS = new Set<String>{
        'id', 'isdeleted', 'createddate', 'createdbyid',
        'lastmodifieddate', 'lastmodifiedbyid', 'systemmodstamp',
        'lastactivitydate', 'lastvieweddate', 'lastreferenceddate'
    };

    public static void enforceLock(List<Quote> newQuotes, Map<Id, Quote> oldMap) {
        if (isSwitchedOff() || oldMap == null) {
            return;
        }

        Id lockedRecordTypeId = residentialSalesRecordTypeId();
        if (lockedRecordTypeId == null) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Quote.fields.getMap();

        for (Quote newQ : newQuotes) {
            Quote oldQ = oldMap.get(newQ.Id);
            if (oldQ == null || oldQ.Status != LOCKED_STATUS) {
                continue;
            }
            if (newQ.RecordTypeId != lockedRecordTypeId) {
                continue;
            }
            // Exempt: transition to Cancelled.
            if (newQ.Status == CANCELLED_STATUS && oldQ.Status != newQ.Status) {
                continue;
            }

            for (String fieldName : fieldMap.keySet()) {
                if (EXEMPT_FIELDS.contains(fieldName) || SYSTEM_FIELDS.contains(fieldName)) {
                    continue;
                }

                Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
                if (dfr.isCalculated() || !dfr.isUpdateable()) {
                    continue; // formula/rollup/system-managed fields aren't genuine edits
                }

                if (newQ.get(fieldName) != oldQ.get(fieldName)) {
                    newQ.addError(ERROR_MESSAGE);
                    break;
                }
            }
        }
    }

    private static Boolean isSwitchedOff() {
        RES_Config_Switch__c cs = RES_Config_Switch__c.getInstance();
        return cs != null && cs.RES_Triggers_Off__c == true;
    }

    private static Id residentialSalesRecordTypeId() {
        Schema.RecordTypeInfo rti = Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName().get(LOCKED_RECORD_TYPE);
        return rti != null ? rti.getRecordTypeId() : null;
    }
}
