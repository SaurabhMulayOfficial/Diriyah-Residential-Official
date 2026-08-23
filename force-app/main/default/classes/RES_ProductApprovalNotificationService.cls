/**
 * =============================================================================
 * Class Name   : RES_ProductApprovalNotificationService
 * Description  : Handles email notifications for Product Approval processing.
 *
 * Responsibilities:
 *      - Notify the next approval team after successful approval.
 *      - Notify Operations after successful final approval.
 *      - Notify Operations after successful rejection.
 *      - Retrieve email templates from CMDT.
 *      - Resolve Public Group members to User email addresses.
 *      - Build email content using CMDT merge placeholders.
 *
 * Framework Rule:
 *      - No SOQL.
 *      - No DML.
 *      - No direct data access.
 *      - Uses DAO classes for data retrieval.
 *      - Uses RES_SendEmailInvocable for email delivery.
 *
 * Approval Flow:
 *
 *      DevCo
 *        |
 *        v
 *      Finance
 *        |
 *        v
 *      CSO
 *        |
 *        v
 *      Approved
 *
 * Rejection Flow:
 *
 *      DevCo / Finance / CSO
 *                  |
 *                  v
 *              Rejected
 *                  |
 *                  v
 *             Operations
 * =============================================================================
 */
public with sharing class RES_ProductApprovalNotificationService {

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    private static final String NEXT_TEAM_TEMPLATE = 'Product_Approval_Next_Team';
    private static final String REJECTION_TEMPLATE = 'Product_Approval_Rejection';

    /*
     * Final approval notification.
     *
     * If a dedicated template is not yet created, the final notification
     * can simply be skipped until the template is configured.
     */
    private static final String FINAL_APPROVAL_TEMPLATE = 'Product_Approval_Final';

    private static final String DEVCO_GROUP = System.Label.RES_Product_Approval_DevCo_Group;
    private static final String FINANCE_GROUP = System.Label.RES_Product_Approval_Finance_Group;
    private static final String CSO_GROUP = System.Label.RES_Product_Approval_CSO_Group;
    private static final String OPERATIONS_GROUP = System.Label.RES_Product_Approval_Operations_Group;

    private static final Integer MAX_EMAIL_RECIPIENTS = 150;

    // =========================================================================
    // DAO DEPENDENCIES
    // =========================================================================

    private static final RES_ApexEmailTemplateDAO EMAIL_TEMPLATE_DAO = new RES_ApexEmailTemplateDAO();
    private static final RES_GroupMemberDAOLayer GROUP_MEMBER_DAO = new RES_GroupMemberDAOLayer();

    // =========================================================================
    // APPROVAL NOTIFICATION
    // =========================================================================

    /**
     * Sends notification to the next approval team.
     *
     * Example:
     *
     * DevCo approves
     *      ->
     * Finance receives notification
     *
     * Finance approves
     *      ->
     * CSO receives notification
     */
    public static void notifyNextApprovalTeam(
        List<Product2> products,
        String currentTeamLabel,
        String nextTeamLabel,
        String nextTeamGroupDeveloperName
    ) {
        if (products == null || products.isEmpty() || String.isBlank(nextTeamGroupDeveloperName)) {
            return;
        }

        Set<String> recipientEmails = getGroupRecipientEmails(nextTeamGroupDeveloperName);
        if (recipientEmails.isEmpty()) {
            return;
        }

        RES_Apex_Email_Template__mdt template = getEmailTemplate(NEXT_TEAM_TEMPLATE);
        if (template == null) {
            return;
        }

        String productDetails = buildProductDetails(products);
        String subject = buildApprovalSubject(template.Subject__c, currentTeamLabel, nextTeamLabel, productDetails);
        String htmlBody = buildApprovalBody(template.Html_Body__c, currentTeamLabel, nextTeamLabel, productDetails);

        sendEmails(recipientEmails, subject, htmlBody);
    }

    // =========================================================================
    // FINAL APPROVAL NOTIFICATION
    // =========================================================================

    /**
     * Sends notification to Operations after final approval.
     *
     * Flow:
     *
     * CSO approves
     *      ->
     * Product becomes Approved
     *      ->
     * Operations is notified
     */
    public static void notifyFinalApproval(List<Product2> products, String approvingTeamLabel) {
        if (products == null || products.isEmpty() || String.isBlank(OPERATIONS_GROUP)) {
            return;
        }

        Set<String> recipientEmails = getGroupRecipientEmails(OPERATIONS_GROUP);
        if (recipientEmails.isEmpty()) {
            return;
        }

        RES_Apex_Email_Template__mdt template = getEmailTemplate(FINAL_APPROVAL_TEMPLATE);
        if (template == null) {
            return;
        }

        String productDetails = buildProductDetails(products);

        String subject = replaceToken(template.Subject__c, '{0}', safeValue(approvingTeamLabel));
        subject = replaceToken(subject, '{1}', safeValue(productDetails));

        String htmlBody = replaceToken(template.Html_Body__c, '{0}', safeValue(approvingTeamLabel));
        htmlBody = replaceToken(htmlBody, '{1}', safeValue(productDetails));

        sendEmails(recipientEmails, subject, htmlBody);
    }

    // =========================================================================
    // REJECTION NOTIFICATION
    // =========================================================================

    /**
     * Sends rejection notification to Operations.
     *
     * Flow:
     *
     * DevCo / Finance / CSO rejects
     *              |
     *              v
     *          Operations
     */
    public static void notifyProductRejection(List<Product2> products, String rejectingTeamLabel, String rejectionReason) {
        if (products == null || products.isEmpty() || String.isBlank(OPERATIONS_GROUP)) {
            return;
        }

        Set<String> recipientEmails = getGroupRecipientEmails(OPERATIONS_GROUP);
        if (recipientEmails.isEmpty()) {
            return;
        }

        RES_Apex_Email_Template__mdt template = getEmailTemplate(REJECTION_TEMPLATE);
        if (template == null) {
            return;
        }

        String productDetails = buildProductDetails(products);
        String subject = buildRejectionSubject(template.Subject__c, rejectingTeamLabel, productDetails, rejectionReason);
        String htmlBody = buildRejectionBody(template.Html_Body__c, rejectingTeamLabel, productDetails, rejectionReason);

        sendEmails(recipientEmails, subject, htmlBody);
    }

    // =========================================================================
    // PUBLIC GROUP RECIPIENTS
    // =========================================================================

    /**
     * Resolves Public Group members to email addresses.
     *
     * The DAO is responsible for resolving the actual group membership.
     */
    private static Set<String> getGroupRecipientEmails(String groupDeveloperName) {
        Set<String> recipients = new Set<String>();
        if (String.isBlank(groupDeveloperName)) {
            return recipients;
        }

        Map<String, Set<String>> groupEmailMap =
            GROUP_MEMBER_DAO.getGroupMembersByGroupNames(new Set<String>{ groupDeveloperName });

        if (groupEmailMap != null && groupEmailMap.containsKey(groupDeveloperName) && groupEmailMap.get(groupDeveloperName) != null) {
            recipients.addAll(groupEmailMap.get(groupDeveloperName));
        }

        return recipients;
    }

    // =========================================================================
    // EMAIL TEMPLATE
    // =========================================================================

    private static RES_Apex_Email_Template__mdt getEmailTemplate(String templateDeveloperName) {
        if (String.isBlank(templateDeveloperName)) {
            return null;
        }

        Map<String, RES_Apex_Email_Template__mdt> templates =
            EMAIL_TEMPLATE_DAO.getApexTemplateByName(new Set<String>{ templateDeveloperName });

        if (templates == null || templates.isEmpty()) {
            return null;
        }

        return templates.get(templateDeveloperName);
    }

    // =========================================================================
    // APPROVAL TEMPLATE
    // =========================================================================

    /**
     * Approval template merge fields:
     *
     * {0} = Next Team
     * {1} = Approving Team
     * {2} = Product Details
     */
    private static String buildApprovalSubject(String subject, String approvingTeam, String nextTeam, String productDetails) {
        String result = safeValue(subject);
        result = replaceToken(result, '{0}', safeValue(nextTeam));
        result = replaceToken(result, '{1}', safeValue(approvingTeam));
        result = replaceToken(result, '{2}', safeValue(productDetails));
        return result;
    }

    private static String buildApprovalBody(String body, String approvingTeam, String nextTeam, String productDetails) {
        String result = safeValue(body);
        result = replaceToken(result, '{0}', escapeHtml(safeValue(nextTeam)));
        result = replaceToken(result, '{1}', escapeHtml(safeValue(approvingTeam)));
        result = replaceToken(result, '{2}', safeValue(productDetails));
        return result;
    }

    // =========================================================================
    // REJECTION TEMPLATE
    // =========================================================================

    /**
     * Rejection template merge fields:
     *
     * {0} = Rejecting Team
     * {1} = Product Details
     * {2} = Rejection Reason
     */
    private static String buildRejectionSubject(String subject, String rejectingTeam, String productDetails, String rejectionReason) {
        String result = safeValue(subject);
        result = replaceToken(result, '{0}', safeValue(rejectingTeam));
        result = replaceToken(result, '{1}', safeValue(productDetails));
        result = replaceToken(result, '{2}', safeValue(rejectionReason));
        return result;
    }

    private static String buildRejectionBody(String body, String rejectingTeam, String productDetails, String rejectionReason) {
        String result = safeValue(body);
        result = replaceToken(result, '{0}', escapeHtml(safeValue(rejectingTeam)));
        result = replaceToken(result, '{1}', safeValue(productDetails));
        result = replaceToken(result, '{2}', escapeHtml(safeValue(rejectionReason)));
        return result;
    }

    // =========================================================================
    // EMAIL SENDING
    // =========================================================================

    private static void sendEmails(Set<String> recipientEmails, String subject, String htmlBody) {
        if (recipientEmails == null || recipientEmails.isEmpty()) {
            return;
        }

        List<String> validEmails = new List<String>();
        for (String emailAddress : recipientEmails) {
            if (!String.isBlank(emailAddress)) {
                validEmails.add(emailAddress.trim());
            }
        }

        if (validEmails.isEmpty()) {
            return;
        }

        List<RES_SendEmailInvocable.inputs> invocableInputs = new List<RES_SendEmailInvocable.inputs>();

        for (Integer startIndex = 0; startIndex < validEmails.size(); startIndex += MAX_EMAIL_RECIPIENTS) {
            Integer endIndex = Math.min(startIndex + MAX_EMAIL_RECIPIENTS, validEmails.size());

            List<String> emailBatch = new List<String>();
            for (Integer index = startIndex; index < endIndex; index++) {
                emailBatch.add(validEmails[index]);
            }

            RES_SendEmailInvocable.inputs input = new RES_SendEmailInvocable.inputs();
            input.recipients = emailBatch;
            input.orgWideEmailAddressId = null;
            input.emailSubject = subject;
            input.emailBody = htmlBody;
            input.mergeFields = new List<String>();

            invocableInputs.add(input);
        }

        if (!invocableInputs.isEmpty()) {
            RES_SendEmailInvocable.sendEmails(invocableInputs);
        }
    }

    // =========================================================================
    // PRODUCT DETAILS
    // =========================================================================

    private static String buildProductDetails(List<Product2> products) {
        if (products == null || products.isEmpty()) {
            return '';
        }

        List<String> details = new List<String>();
        for (Product2 productRecord : products) {
            if (productRecord == null || productRecord.Id == null) {
                continue;
            }

            String detail = '<strong>' + escapeHtml(productRecord.Name) + '</strong>';
            if (!String.isBlank(productRecord.ProductCode)) {
                detail += ' (' + escapeHtml(productRecord.ProductCode) + ')';
            }

            details.add('<li>' + detail + '</li>');
        }

        if (details.isEmpty()) {
            return '';
        }

        return '<ul>' + String.join(details, '') + '</ul>';
    }

    // =========================================================================
    // COMMON HELPERS
    // =========================================================================

    private static String replaceToken(String content, String token, String value) {
        if (String.isBlank(content)) {
            return '';
        }
        return content.replace(token, value == null ? '' : value);
    }

    private static String safeValue(String value) {
        return String.isBlank(value) ? '' : value;
    }

    private static String escapeHtml(String value) {
        if (String.isBlank(value)) {
            return '';
        }

        String result = value;
        result = result.replace('&', '&amp;');
        result = result.replace('<', '&lt;');
        result = result.replace('>', '&gt;');
        result = result.replace('"', '&quot;');
        result = result.replace('\'', '&#39;');

        return result;
    }
}