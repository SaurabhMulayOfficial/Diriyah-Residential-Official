/**
 * @description Builds the Payment Plan details and schedule table rows for the approver email sent by
 *              RES_Payment_Plan_Send_Approval_Notification (template RES_Payment_Plan_Approval_Notification,
 *              merge fields {5} and {6}).
 *
 *              Plan details : Project, Payment Plan ID (SAP), Payment Plan Description, Payment Plan Duration
 *              Schedule     : Sales Instalments (Condition Type), Percentage, Months, POC
 *              Attachments  : when includeAttachments = true (the flows' default, so every approval email): latest version of each file
 *                             on the plan record (newest first, Notes excluded), kept under MAX_ATTACHMENT_BYTES so
 *                             the email stays within the 25 MB limit.
 *
 *              Never throws: a failure returns blank rows / no attachments so the approval email is still sent.
 */
public without sharing class RES_PaymentPlanEmailDetailsInvocable {

    private static final RES_Product2DAOLayer PRODUCT_DAO = new RES_Product2DAOLayer();
    private static final RES_ContentDocumentLinkDAOLayer FILE_LINK_DAO = new RES_ContentDocumentLinkDAOLayer();

    @TestVisible
    private static final Integer MAX_ATTACHMENT_BYTES = 20 * 1024 * 1024;
    private static final String NOTE_FILE_TYPE = 'SNOTE';

    private static final String LABEL_CELL_STYLE =
        'padding:8px;border:1px solid #EADFC9;background-color:#FBF8F2;color:#4A3103;font-family:Arial,Helvetica,sans-serif;font-size:13px;font-weight:bold;width:45%;';
    private static final String VALUE_CELL_STYLE =
        'padding:8px;border:1px solid #EADFC9;color:#444444;font-family:Arial,Helvetica,sans-serif;font-size:13px;';

    public class Request {
        @InvocableVariable(label='Payment Plan Id' required=true)
        public String recordId;

        @InvocableVariable(label='Include Attachments' description='Return the files on the Payment Plan record as attachments.')
        public Boolean includeAttachments = false;
    }

    public class Response {
        @InvocableVariable(label='Plan Details Rows HTML')
        public String planDetailsHtml = '';

        @InvocableVariable(label='Schedule Rows HTML')
        public String scheduleRowsHtml = '';

        @InvocableVariable(label='Attachment Ids' description='ContentVersion Ids of the files on the Payment Plan record.')
        public List<String> attachmentIds = new List<String>();
    }

    @InvocableMethod(label='Get Payment Plan Email Details' description='Builds the plan details and installment schedule table rows for the payment plan approval email.')
    public static List<Response> getEmailDetails(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }

        Set<Id> planIds = new Set<Id>();
        for (Request request : requests) {
            Id planId = toId(request?.recordId);
            if (planId != null) {
                planIds.add(planId);
            }
        }

        Map<Id, Product2> plansById = new Map<Id, Product2>();
        try {
            plansById.putAll(PRODUCT_DAO.getPaymentPlanEmailDetailsByIds(planIds));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '### [RES_PaymentPlanEmailDetailsInvocable] Plan lookup failed: ' + e.getMessage());
        }

        Set<Id> planIdsWithAttachments = new Set<Id>();
        for (Request request : requests) {
            Id planId = toId(request?.recordId);
            if (request?.includeAttachments == true && plansById.containsKey(planId)) {
                planIdsWithAttachments.add(planId);
            }
        }

        Map<Id, List<String>> attachmentIdsByPlanId = new Map<Id, List<String>>();
        try {
            if (!planIdsWithAttachments.isEmpty()) {
                attachmentIdsByPlanId = getAttachmentIdsByPlanId(planIdsWithAttachments);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '### [RES_PaymentPlanEmailDetailsInvocable] File lookup failed: ' + e.getMessage());
        }

        for (Request request : requests) {
            Response response = new Response();
            Product2 plan = plansById.get(toId(request?.recordId));
            if (plan != null && request.includeAttachments == true && attachmentIdsByPlanId.containsKey(plan.Id)) {
                response.attachmentIds = attachmentIdsByPlanId.get(plan.Id);
            }
            if (plan != null) {
                try {
                    response.planDetailsHtml = buildPlanDetailsRows(plan);
                    response.scheduleRowsHtml = buildScheduleRows(RES_InstallmentListController.getInstallments(plan.Id));
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, '### [RES_PaymentPlanEmailDetailsInvocable] Build failed for ' + plan.Id + ': ' + e.getMessage());
                }
            }
            responses.add(response);
        }
        return responses;
    }

    @TestVisible
    private static Map<Id, List<String>> getAttachmentIdsByPlanId(Set<Id> planIds) {
        Map<Id, List<String>> result = new Map<Id, List<String>>();
        Map<Id, Integer> bytesByPlanId = new Map<Id, Integer>();
        for (ContentDocumentLink link : FILE_LINK_DAO.getEmailAttachmentLinksByLinkedIds(planIds)) {
            ContentDocument file = link.ContentDocument;
            if (file == null || file.LatestPublishedVersionId == null || file.FileType == NOTE_FILE_TYPE) {
                continue;
            }
            Integer size = file.ContentSize ?? 0;
            Integer used = bytesByPlanId.get(link.LinkedEntityId) ?? 0;
            if (used + size > MAX_ATTACHMENT_BYTES) {
                System.debug(LoggingLevel.WARN, '### [RES_PaymentPlanEmailDetailsInvocable] Skipped "' + file.Title + '": email attachment limit reached');
                continue;
            }
            if (!result.containsKey(link.LinkedEntityId)) {
                result.put(link.LinkedEntityId, new List<String>());
            }
            result.get(link.LinkedEntityId).add(file.LatestPublishedVersionId);
            bytesByPlanId.put(link.LinkedEntityId, used + size);
        }
        return result;
    }

    @TestVisible
    private static String buildPlanDetailsRows(Product2 plan) {
        // A modification draft is synced to SAP under its parent plan's ID, same as RES_PaymentPlanIntegrationService
        String sapPlanId = plan.RES_Parent_Payment_Plan__r?.RES_Product_External_ID__c ?? plan.RES_Product_External_ID__c;

        return buildDetailRow('Project', plan.RES_Business_Entity__r?.Name)
            + buildDetailRow('Payment Plan ID', sapPlanId)
            + buildDetailRow('Payment Plan Description', plan.Name)
            + buildDetailRow('Payment Plan Duration', formatDuration(plan.RES_No_of_Years__c, plan.RES_No_of_Months__c));
    }

    @TestVisible
    private static String buildScheduleRows(List<RES_InstallmentListController.Installment> installments) {
        if (installments == null || installments.isEmpty()) {
            return '<tr><td colspan="4" style="' + VALUE_CELL_STYLE + 'text-align:center;">No installments defined.</td></tr>';
        }

        List<String> rows = new List<String>();
        for (RES_InstallmentListController.Installment installment : installments) {
            rows.add(
                '<tr>' +
                buildScheduleCell(installment.conditionType ?? installment.name) +
                buildScheduleCell(formatPercent(installment.percentage)) +
                buildScheduleCell(installment.conditionMonths != null ? String.valueOf(installment.conditionMonths.intValue()) : null) +
                buildScheduleCell(formatPercent(installment.pocPercentage)) +
                '</tr>'
            );
        }
        return String.join(rows, '');
    }

    private static String buildDetailRow(String label, String value) {
        return '<tr>' +
            '<td style="' + LABEL_CELL_STYLE + '">' + label + '</td>' +
            '<td style="' + VALUE_CELL_STYLE + '">' + displayValue(value) + '</td>' +
            '</tr>';
    }

    private static String buildScheduleCell(String value) {
        return '<td style="' + VALUE_CELL_STYLE + 'text-align:center;">' + displayValue(value) + '</td>';
    }

    @TestVisible
    private static String formatDuration(Decimal years, Decimal months) {
        if (years != null) {
            return years.stripTrailingZeros().toPlainString() + (years == 1 ? ' Year' : ' Years');
        }
        if (months != null) {
            return months.stripTrailingZeros().toPlainString() + (months == 1 ? ' Month' : ' Months');
        }
        return null;
    }

    private static String formatPercent(Decimal value) {
        return value == null ? null : value.setScale(2).toPlainString() + '%';
    }

    private static String displayValue(String value) {
        return String.isBlank(value) ? '-' : value.escapeHtml4();
    }

    private static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value.trim());
        } catch (Exception e) {
            return null;
        }
    }
}