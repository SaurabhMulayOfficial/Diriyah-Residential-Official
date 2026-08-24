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
public without sharing class RES_ProductApprovalNotificationService {

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    private static final String NEXT_TEAM_TEMPLATE = 'Product_Approval_Next_Team';
    private static final String REJECTION_TEMPLATE = 'Product_Approval_Rejection';
    private static final String FINAL_APPROVAL_TEMPLATE = 'Product_Approval_Final';

    private static final String DEVCO_GROUP = System.Label.RES_Product_Approval_DevCo_Group;
    private static final String FINANCE_GROUP = System.Label.RES_Product_Approval_Finance_Group;
    private static final String CSO_GROUP = System.Label.RES_Product_Approval_CSO_Group;
    private static final String OPERATIONS_GROUP = System.Label.RES_Product_Approval_Operations_Group;

    private static final Integer MAX_EMAIL_RECIPIENTS = 150;

    /*
     * Org-Wide Email Address configuration.
     *
     * The Custom Label 'Org_Wide_Email' should contain the
     * Display Name of the Org-Wide Email Address.
     *
     * Example:
     * Salesforce Notifications
     *
     * If the label is blank or the Org-Wide Email Address
     * cannot be found, null is returned.
     */
    private static final String ORG_WIDE_EMAIL_DISPLAY_NAME = System.Label.Org_Wide_Email;

    private static Id cachedOrgWideEmailAddressId;

    // =========================================================================
    // DAO DEPENDENCIES
    // =========================================================================

    private static final RES_ApexEmailTemplateDAO EMAIL_TEMPLATE_DAO = new RES_ApexEmailTemplateDAO();
    private static final RES_GroupMemberDAOLayer GROUP_MEMBER_DAO = new RES_GroupMemberDAOLayer();
    private static final RES_OrgWideAddressDAO ORG_WIDE_EMAIL_DAO = new RES_OrgWideAddressDAO();

    // =========================================================================
    // APPROVAL NOTIFICATION
    // =========================================================================

    /**
     * Sends notification to the next approval team.
     *
     * Template merge fields:
     * {0} = Next Team
     * {1} = Approving Team
     * {2} = Product Details
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

        List<String> mergeFieldsForSubject = new List<String>{ nextTeamLabel, currentTeamLabel, productDetails };
        List<String> mergeFieldsForBody = new List<String>{
            escapeHtml(safeValue(nextTeamLabel)),
            escapeHtml(safeValue(currentTeamLabel)),
            productDetails
        };

        sendEmailsWithMergeFields(recipientEmails, template.Subject__c, template.Html_Body__c, mergeFieldsForSubject, mergeFieldsForBody);
    }

    // =========================================================================
    // FINAL APPROVAL NOTIFICATION
    // =========================================================================

    /**
     * Sends notification to Operations after final approval.
     *
     * Template merge fields:
     * {0} = Approving Team
     * {1} = Product Details
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

        List<String> mergeFieldsForSubject = new List<String>{ approvingTeamLabel, productDetails };
        List<String> mergeFieldsForBody = new List<String>{ escapeHtml(safeValue(approvingTeamLabel)), productDetails };

        sendEmailsWithMergeFields(recipientEmails, template.Subject__c, template.Html_Body__c, mergeFieldsForSubject, mergeFieldsForBody);
    }

    // =========================================================================
    // REJECTION NOTIFICATION
    // =========================================================================

    /**
     * Sends rejection notification to Operations.
     *
     * Template merge fields:
     * {0} = Rejecting Team
     * {1} = Product Details
     * {2} = Rejection Reason
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

        List<String> mergeFieldsForSubject = new List<String>{ rejectingTeamLabel, productDetails, rejectionReason };
        List<String> mergeFieldsForBody = new List<String>{
            escapeHtml(safeValue(rejectingTeamLabel)),
            productDetails,
            escapeHtml(safeValue(rejectionReason))
        };

        sendEmailsWithMergeFields(recipientEmails, template.Subject__c, template.Html_Body__c, mergeFieldsForSubject, mergeFieldsForBody);
    }

    // =========================================================================
    // PUBLIC GROUP RECIPIENTS
    // =========================================================================

    /**
     * Resolves Public Group members to email addresses.
     */
    private static Set<String> getGroupRecipientEmails(String groupDeveloperName) {
        Set<String> recipients = new Set<String>();
        if (String.isBlank(groupDeveloperName)) {
            return recipients;
        }

        Map<String, Set<String>> groupEmailMap = GROUP_MEMBER_DAO.getGroupMembersByGroupNames(new Set<String>{ groupDeveloperName });

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
    // EMAIL SENDING
    // =========================================================================

    /**
     * Sends emails with merge field replacement.
     *
     * This method leverages RES_EmailUtilityService.hydrateMergeFields()
     * to replace {0}, {1}, {2} tokens in templates.
     */
    private static void sendEmailsWithMergeFields(
        Set<String> recipientEmails,
        String subjectTemplate,
        String bodyTemplate,
        List<String> mergeFieldsForSubject,
        List<String> mergeFieldsForBody
    ) {
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

        String mergedSubject = RES_EmailUtilityService.hydrateMergeFields(subjectTemplate, mergeFieldsForSubject);

        List<RES_SendEmailInvocable.inputs> invocableInputs = new List<RES_SendEmailInvocable.inputs>();

        for (Integer startIndex = 0; startIndex < validEmails.size(); startIndex += MAX_EMAIL_RECIPIENTS) {
            Integer endIndex = Math.min(startIndex + MAX_EMAIL_RECIPIENTS, validEmails.size());

            List<String> emailBatch = new List<String>();
            for (Integer index = startIndex; index < endIndex; index++) {
                emailBatch.add(validEmails[index]);
            }

            RES_SendEmailInvocable.inputs input = new RES_SendEmailInvocable.inputs();
            input.recipients = emailBatch;

            // Resolve Org-Wide Email Address ID from Custom Label.
            input.orgWideEmailAddressId = getOrgWideEmailAddressId();

            input.emailSubject = mergedSubject;
            input.emailBody = bodyTemplate;

            // RES_EmailUtilityService.setHtmlBody()
            // handles merge field replacement.
            input.mergeFields = mergeFieldsForBody;

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
    // ORG-WIDE EMAIL ADDRESS
    // =========================================================================

    /**
     * Retrieves the Org-Wide Email Address ID using the
     * Display Name configured in the Org_Wide_Email Custom Label.
     *
     * The actual SOQL is handled by RES_OrgWideAddressDAO.
     */
    private static Id getOrgWideEmailAddressId() {
        if (cachedOrgWideEmailAddressId != null) {
            return cachedOrgWideEmailAddressId;
        }

        if (String.isBlank(ORG_WIDE_EMAIL_DISPLAY_NAME)) {
            return null;
        }

        try {
            List<OrgWideEmailAddress> orgWideAddresses = ORG_WIDE_EMAIL_DAO.getOrgWideAddressByDisplayName(ORG_WIDE_EMAIL_DISPLAY_NAME);
            if (orgWideAddresses != null && !orgWideAddresses.isEmpty()) {
                cachedOrgWideEmailAddressId = orgWideAddresses[0].Id;
            }
            return cachedOrgWideEmailAddressId;
        } catch (Exception e) {
            return null;
        }
    }

    // =========================================================================
    // COMMON HELPERS
    // =========================================================================

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