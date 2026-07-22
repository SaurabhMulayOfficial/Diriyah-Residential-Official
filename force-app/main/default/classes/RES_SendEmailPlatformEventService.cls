public without sharing class RES_SendEmailPlatformEventService {
    public RES_SendEmailPlatformEventService() {}

    public static void processEventsForDuplicationEmails(List<RES_Send_Email__e> events){
        if (events == null || events.isEmpty()) {
            return;
        }

        List<RES_Send_Email__e> eventsToProcess = new List<RES_Send_Email__e>();
        for(RES_Send_Email__e e: events){
            if(e.Type__c == 'Lead Duplication'){
                eventsToProcess.add(e);
            }
        }

        if(eventsToProcess.size() <= 0){
            return;
        }

        Set<String> groupNames = new Set<String>();
        for(RES_Send_Email__e e: eventsToProcess){
            if(e.Group__c != null){
                groupNames.add(e.Group__c);
            }
        }

        Map<String, Set<String>> groupToEmailsMapping = new RES_GroupMemberDAOLayer().getGroupMembersByGroupNames(groupNames);
        List<RES_EmailUtilityService> emailUtility = new List<RES_EmailUtilityService>();
                                    
        Set<String> templates = new Set<String>();
        String operationTeamTemplate = SYSTEM.Label.RES_Deduplication_Templates;
        templates.add(operationTeamTemplate);

        Map<String, RES_Apex_Email_Template__mdt> apexTemplates = new RES_ApexEmailTemplateDAO().getApexTemplateByName(templates);

        if(apexTemplates.containsKey(operationTeamTemplate)){
            RES_Apex_Email_Template__mdt operationEmailTemplate = apexTemplates.get(operationTeamTemplate);
            String htmlBody = operationEmailTemplate.Html_Body__c;
            String subject = operationEmailTemplate.Subject__c;

            for(RES_Send_Email__e event: eventsToProcess){
                if(event.OrgWideAddressID__c == null ){
                    continue;
                }
                List<String> mergeFields = String.isBlank(event.Merge_Fields__c)
                        ? new List<String>()
                        : event.Merge_Fields__c.split(',');

                if(groupToEmailsMapping.containsKey(event.Group__c)){
                    Set<String> emails = groupToEmailsMapping.get(event.Group__c);

                    for(String email: emails){
                        RES_EmailUtilityService utilNode = new RES_EmailUtilityService();
                        utilNode.setToAddresses(new List<String>{email});
                        utilNode.setHtmlBody(htmlBody,mergeFields);
                        utilNode.setOrgWideEmailAddressId(event.OrgWideAddressID__c);
                        utilNode.setSubject(subject);
                        emailUtility.add(utilNode);
                    }
                }
            }
        }

        if(emailUtility.size() > 0){
            try{
                RES_EmailService.sendEmail(emailUtility);
            }
            catch(Exception e){
                System.debug('Exception Sending Lead Duplication Emails Through Platform Event ' + e.getMessage());
            }
        }
    } 
}