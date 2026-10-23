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
    private static final Integer PRICE_DECIMAL_PLACES = 3;
    private static final String APPROVAL_TEMPLATE = 'Product_Approval_Notification';
    private static final String FINAL_APPROVAL_TEMPLATE = 'Product_Final_Approval_Notification';
    private static final String REJECTION_TEMPLATE = 'Product_Rejection_Notification';
    private static final String UPDATE_NOTIFICATION_TEMPLATE = 'Product_Update_Notification';

    private static final String DEVCO_GROUP = System.Label.RES_Product_Approval_DevCo_Group;
    private static final String FINANCE_GROUP = System.Label.RES_Product_Approval_Finance_Group;
    private static final String CSO_GROUP = System.Label.RES_Product_Approval_CSO_Group;
    private static final String OPERATIONS_GROUP = System.Label.RES_Product_Approval_Operations_Group;

    private static final Integer MAX_EMAIL_RECIPIENTS = 150;

    /*
     * Org-Wide Email Address configuration.
     */
    private static final String ORG_WIDE_EMAIL_DISPLAY_NAME = System.Label.Org_Wide_Email;

    private static Id cachedOrgWideEmailAddressId;

    private static final RES_ApexEmailTemplateDAO EMAIL_TEMPLATE_DAO = new RES_ApexEmailTemplateDAO();
    private static final RES_GroupMemberDAOLayer GROUP_MEMBER_DAO = new RES_GroupMemberDAOLayer();
    private static final RES_OrgWideAddressDAO ORG_WIDE_EMAIL_DAO = new RES_OrgWideAddressDAO();
    private static final RES_PricebookEntryDAOLayer PRICEBOOK_ENTRY_DAO = new RES_PricebookEntryDAOLayer();

    private static final String UNIT_TABLE_CELL_STYLE =
        'padding:8px;border:1px solid #EADFC9;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#444444;';
    /**
     * Sends notification to the next approval team.
     *
     * Template merge fields:
     * {0} = Recipient Team Name
     * {1} = Sender Team Name
     * {2} = Action Verb (e.g., "submitted", "forwarded")
     * {3} = Unit Count
     * {4} = Full URL to Product Approval Queue
     * {5} = Unit details table rows (Company Code, Project/District, RU No., Inventory Type, Property Price)
     */
    public static void notifyNextApprovalTeam(List<Product2> products, String currentTeamLabel, String nextTeamLabel, String nextTeamGroupDeveloperName) {
        if (products == null || products.isEmpty() || String.isBlank(nextTeamGroupDeveloperName)) {
            return;
        }

        Set<String> recipientEmails = getGroupRecipientEmails(nextTeamGroupDeveloperName);
        if (recipientEmails.isEmpty()) {
            return;
        }

        RES_Apex_Email_Template__mdt template = getEmailTemplate(APPROVAL_TEMPLATE);
        if (template == null) {
            return;
        }

        String unitCount = String.valueOf(products.size());
        String approvalQueueUrl = getApprovalQueueUrl();

        List<String> mergeFieldsForSubject = new List<String>{ unitCount };
        List<String> mergeFieldsForBody = new List<String>{
            escapeHtml(safeValue(nextTeamLabel)),
            escapeHtml(safeValue(currentTeamLabel)),
            'forwarded',
            unitCount,
            approvalQueueUrl,
            buildUnitTableRows(products)
        };

        sendEmailsWithMergeFields(recipientEmails, template.Subject__c, template.Html_Body__c, mergeFieldsForSubject, mergeFieldsForBody);
    }
    /**
     * Sends notification to Operations after final approval.
     * Uses special final approval template to celebrate completion.
     *
     * Template merge fields:
     * {0} = Recipient Team Name (Operations)
     * {1} = Approving Team Name (CSO Team)
     * {2} = Unit Count
     * {3} = Full URL to Product Approval Queue
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

        String unitCount = String.valueOf(products.size());
        String approvalQueueUrl = getApprovalQueueUrl();

        List<String> mergeFieldsForSubject = new List<String>{ unitCount };
        List<String> mergeFieldsForBody = new List<String>{
            'Operations Team',
            escapeHtml(safeValue(approvingTeamLabel)),
            unitCount,
            approvalQueueUrl
        };

        sendEmailsWithMergeFields(recipientEmails, template.Subject__c, template.Html_Body__c, mergeFieldsForSubject, mergeFieldsForBody);
    }

    /**
     * Sends rejection notification to Operations.
     *
     * Template merge fields:
     * {0} = Recipient Team Name (Operations)
     * {1} = Rejecting Team Name
     * {2} = Unit Count
     * {3} = Rejection Reason
     * {4} = Full URL to Product Approval Queue
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

        String unitCount = String.valueOf(products.size());
        String approvalQueueUrl = getApprovalQueueUrl();

        List<String> mergeFieldsForSubject = new List<String>{ unitCount };
        List<String> mergeFieldsForBody = new List<String>{
            'Operations Team',
            escapeHtml(safeValue(rejectingTeamLabel)),
            unitCount,
            escapeHtml(safeValue(rejectionReason)),
            approvalQueueUrl
        };

        sendEmailsWithMergeFields(recipientEmails, template.Subject__c, template.Html_Body__c, mergeFieldsForSubject, mergeFieldsForBody);
    }

    // =========================================================================
    // PRODUCT UPDATE NOTIFICATION
    // =========================================================================

    /**
     * Sends notification to Operations when products are updated and moved to Draft.
     *
     * Template merge fields:
     * {0} = Unit Count (for subject)
     * {1} = Unit Count (for body)
     * {2} = Full URL to Draft & Rejected Queue
     */
    public static void notifyProductUpdate(List<Product2> products) {
        if (products == null || products.isEmpty() || String.isBlank(OPERATIONS_GROUP)) {
            return;
        }

        Set<String> recipientEmails = getGroupRecipientEmails(OPERATIONS_GROUP);
        if (recipientEmails.isEmpty()) {
            return;
        }

        RES_Apex_Email_Template__mdt template = getEmailTemplate(UPDATE_NOTIFICATION_TEMPLATE);
        if (template == null) {
            // Fallback to approval template if update template doesn't exist
            template = getEmailTemplate(APPROVAL_TEMPLATE);
            if (template == null) {
                return;
            }
        }

        String unitCount = String.valueOf(products.size());
        String approvalQueueUrl = getApprovalQueueUrl();

        List<String> mergeFieldsForSubject = new List<String>{ unitCount };
        List<String> mergeFieldsForBody = new List<String>{
            'Operations Team',
            'System',
            'updated',
            unitCount,
            approvalQueueUrl,
            buildUnitTableRows(products)
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
    // UNIT DETAILS TABLE
    // =========================================================================

    /**
     * Builds the <tr> rows for the unit details table in the approval email.
     *
     * Column mapping:
     *      Company Code     = RES_Business_Entity__r.RES_Company_Code__c
     *      Project/District = RES_Business_Entity__r.Name
     *      RU No.           = ProductCode
     *      Inventory Type   = RES_Type__c (picklist label)
     *      Property Price   = unit price under the default Payment Plan (Adjustment Value); falls back to the
     *                         Standard Price Book UnitPrice. Always shown with 3 decimals, e.g. 0.000, 5,273,032.000, 0.123
     *
     * Products must be queried via RES_Product2DAOLayer.getProductsByIds().
     */
    @TestVisible
    private static String buildUnitTableRows(List<Product2> products) {
        if (products == null || products.isEmpty()) {
            return '';
        }

        Map<Id, Decimal> priceByProductId = getStandardPriceByProductId(products);
        Map<Id, Decimal> planPriceByProductId = getDefaultPlanPriceByProductId(products);
        Map<String, String> inventoryTypeLabels = getInventoryTypeLabels();

        List<String> rows = new List<String>();
        for (Product2 product : products) {
            String companyCode = product.RES_Business_Entity__r != null ? product.RES_Business_Entity__r.RES_Company_Code__c : null;
            String project = product.RES_Business_Entity__r != null ? product.RES_Business_Entity__r.Name : null;
            String inventoryType = String.isBlank(product.RES_Type__c)
                ? null
                : (inventoryTypeLabels.containsKey(product.RES_Type__c) ? inventoryTypeLabels.get(product.RES_Type__c) : product.RES_Type__c);
            Decimal price = product.Id != null ? planPriceByProductId.get(product.Id) : null;
            if (price == null && product.Id != null) {
                price = priceByProductId.get(product.Id);
            }

            rows.add(
                '<tr>' +
                buildUnitTableCell(companyCode, 'left') +
                buildUnitTableCell(project, 'left') +
                buildUnitTableCell(product.ProductCode, 'left') +
                buildUnitTableCell(inventoryType, 'left') +
                buildUnitTableCell(formatPrice(price, product.CurrencyIsoCode), 'right') +
                '</tr>'
            );
        }

        return String.join(rows, '');
    }

    private static String buildUnitTableCell(String value, String alignment) {
        String displayValue = String.isBlank(value) ? '-' : escapeHtml(value);
        return '<td style="' + UNIT_TABLE_CELL_STYLE + 'text-align:' + alignment + ';">' + displayValue + '</td>';
    }

    /** Unit price under each unit's default Payment Plan; units without one are omitted. Never blocks the email on failure. */
    private static Map<Id, Decimal> getDefaultPlanPriceByProductId(List<Product2> products) {
        Set<Id> productIds = new Set<Id>();
        for (Product2 product : products) {
            if (product.Id != null) {
                productIds.add(product.Id);
            }
        }
        try {
            return RES_DefaultPlanPriceService.getDefaultPlanPrices(productIds);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'RES_NOTIFY: default plan price lookup failed - ' + e.getMessage());
            return new Map<Id, Decimal>();
        }
    }

    /**
     * Locale-independent price text with a fixed 3 decimals, e.g. 0.000 SAR, 5,273,032.000 SAR, 90,000,000.123 SAR.
     * Rounds half up; null amount renders no value (the cell shows a dash). A blank currency falls back to the running user's default currency.
     */
    @TestVisible
    private static String formatPrice(Decimal amount, String currencyIsoCode) {
        if (amount == null) {
            return null;
        }
        Decimal rounded = amount.setScale(PRICE_DECIMAL_PLACES, RoundingMode.HALF_UP);
        Decimal whole = rounded.setScale(0, RoundingMode.DOWN);
        String digits = String.valueOf(whole.abs());
        String grouped = '';
        while (digits.length() > 3) {
            grouped = ',' + digits.right(3) + grouped;
            digits = digits.left(digits.length() - 3);
        }
        grouped = (rounded < 0 ? '-' : '') + digits + grouped;
        String fraction = String.valueOf((rounded - whole).abs()).substringAfter('.').rightPad(PRICE_DECIMAL_PLACES, '0');
        return grouped + '.' + fraction.left(PRICE_DECIMAL_PLACES) + ' ' + (String.isBlank(currencyIsoCode) ? UserInfo.getDefaultCurrency() : currencyIsoCode);
    }

    private static Map<Id, Decimal> getStandardPriceByProductId(List<Product2> products) {
        Map<Id, Decimal> priceByProductId = new Map<Id, Decimal>();

        Set<Id> productIds = new Set<Id>();
        for (Product2 product : products) {
            if (product.Id != null) {
                productIds.add(product.Id);
            }
        }

        Id standardPricebookId = getStandardPricebookId();
        if (productIds.isEmpty() || standardPricebookId == null) {
            return priceByProductId;
        }

        for (PricebookEntry entry : PRICEBOOK_ENTRY_DAO.getEntriesByBookAndProducts(standardPricebookId, productIds, false)) {
            if (entry.UnitPrice != null && !priceByProductId.containsKey(entry.Product2Id)) {
                priceByProductId.put(entry.Product2Id, entry.UnitPrice);
            }
        }

        return priceByProductId;
    }

    /**
     * Test context hides the Standard Price Book's Pricebook2 row from
     * "Pricebook2.IsStandard = true" filters, so resolve its Id directly.
     */
    private static Id getStandardPricebookId() {
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }
        List<Pricebook2> standardPricebooks = new RES_Pricebook2DAOLayer().getStandardPricebook();
        return standardPricebooks.isEmpty() ? null : standardPricebooks[0].Id;
    }

    private static Map<String, String> getInventoryTypeLabels() {
        Map<String, String> labelsByValue = new Map<String, String>();
        for (Schema.PicklistEntry entry : Product2.RES_Type__c.getDescribe().getPicklistValues()) {
            labelsByValue.put(entry.getValue(), entry.getLabel());
        }
        return labelsByValue;
    }

    // =========================================================================
    // APPROVAL QUEUE URL
    // =========================================================================

    /**
     * Returns the full URL to the Product Approval Queue Lightning page.
     * Uses the current Salesforce instance base URL.
     */
    private static String getApprovalQueueUrl() {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        return baseUrl + '/lightning/n/Product_Approval_Queue';
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