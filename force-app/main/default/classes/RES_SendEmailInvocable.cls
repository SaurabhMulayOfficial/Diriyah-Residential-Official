public with sharing class RES_SendEmailInvocable {
    public RES_SendEmailInvocable() {}

    @InvocableMethod(label='Send Email with Merge Fields' description='Send an email to the specified recipients with merge templates.')

    public static void sendEmails(List<inputs> inputList){
        
        List<RES_EmailUtilityService> emailServices = new List<RES_EmailUtilityService>();

        for(inputs input: inputList){
            RES_EmailUtilityService emailService = new RES_EmailUtilityService();
            emailService.setToAddresses(input.recipients);
            emailService.setOrgWideEmailAddressId(input.orgWideEmailAddressId);
            emailService.setSubject(input.emailSubject, input.subjectMergeFields);
            emailService.setHtmlBody(input.emailBody, input.mergeFields);

            emailServices.add(emailService);
        }

        try{   
            RES_EmailService.sendEmail(emailServices);
        }catch(Exception e){
            System.debug('Error sending email from : RES_SendEmailInvocable.sendEmails ' + e.getMessage());
        }
    }
    
    public class inputs{
        @InvocableVariable(required=true)
        public Id orgWideEmailAddressId;

        @InvocableVariable(required=true)
        public String emailBody;

        @InvocableVariable(required=true)
        public String emailSubject;

        @InvocableVariable(required=true)
        public List<String> recipients;

        @InvocableVariable(required=true)
        public List<String> mergeFields;

        @InvocableVariable(required=true)
        public List<String> subjectMergeFields;
    }
}