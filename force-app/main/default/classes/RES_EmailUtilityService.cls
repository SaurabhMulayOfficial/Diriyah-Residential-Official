/**
 * @description
 * Utility service responsible for constructing and configuring
 * Messaging.SingleEmailMessage instances.
 *
 * This class provides a simplified abstraction over Salesforce's
 * Messaging.SingleEmailMessage API and supports configuring common
 * email properties such as:
 *
 * - To, CC, and BCC recipients
 * - Subject
 * - HTML body
 * - Plain-text body
 * - Email templates
 * - Target and related records
 * - Org-Wide Email Address
 * - Activity tracking
 *
 * The class also provides support for custom positional merge fields
 * using placeholders in the following format:
 *
 *      {0}, {1}, {2}, ...
 *
 * Example:
 *
 *      String template = 'Hello {0}, your lead is {1}.';
 *
 *      List<String> mergeFields = new List<String>{
 *          'John Doe',
 *          'created successfully'
 *      };
 *
 *      String result = hydrateMergeFields(
 *          template,
 *          mergeFields
 *      );
 *
 * The resulting text will be:
 *
 *      Hello John Doe, your lead is created successfully.
 *
 * This utility is responsible for preparing email messages.
 * The actual sending of one or more prepared email messages is
 * handled by RES_EmailService.
 *
 * @author Saurabh Mulay
 * @date
 */

public class RES_EmailUtilityService {
    public Messaging.SingleEmailMessage email;

    public RES_EmailUtilityService() {
        this.email = new Messaging.SingleEmailMessage();
    }

    public static string hydrateMergeFields(String template, List<String> mergeFields){
        if (String.isBlank(template) || mergeFields == null) {
            return template;
        }

        for(integer i = 0; i < mergeFields.size(); i++){
            String mergeValue = mergeFields[i] == null
            ? ''
            : mergeFields[i];

            template = template.replace('{' + String.valueOf(i) + '}', mergeValue);
        }

        return template;
    }

    public virtual void setToAddresses(List<String> toAddresses){
        email.setToAddresses(toAddresses);
    }

    public virtual void setCcAddresses(List<String> ccAddresses){
        email.setCcAddresses(ccAddresses);
    }

    public virtual void setBccAddresses(List<String> bccAddresses){
        email.setBccAddresses(bccAddresses);
    }

    public virtual void setSubject(String subject){
        email.setSubject(subject);
    }

    public virtual void setOrgWideEmailAddressId(Id orgWideEmailAddressId) {
        email.setOrgWideEmailAddressId(orgWideEmailAddressId);
    }

    public virtual void setHtmlBody(String htmlBody, List<String> mergeFields){
        if(mergeFields != null && mergeFields.size() > 0){
            htmlBody = hydrateMergeFields(htmlBody, mergeFields);
        }
        email.setHtmlBody(htmlBody);
    }

    public virtual void setHtmlBody(String htmlBody) {
        email.setHtmlBody(htmlBody);
    }

    public virtual void setPlainTextBody(String plainTextBody) {
        email.setPlainTextBody(plainTextBody);
    }

    public virtual void setPlainTextBody(String plainTextBody, List<String> mergeFields){
        if(mergeFields != null && mergeFields.size() > 0){
            plainTextBody = hydrateMergeFields(plainTextBody, mergeFields);
        }
        email.setPlainTextBody(plainTextBody);
    }

    public virtual void setTemplateId(String templateId){
        email.setTemplateId(templateId);
    }

    public virtual void setWhatId(Id whatId){
        email.setWhatId(whatId);
    }
    
    public virtual void setTargetObjectId(Id targetObjectId){
        email.setTargetObjectId(targetObjectId);
    }

    public virtual void setSaveAsActivity(Boolean saveAsActivity){
        email.setSaveAsActivity(saveAsActivity);
    }
    
    public Messaging.SingleEmailMessage getEmailInstance() {
        return this.email;
    }
}