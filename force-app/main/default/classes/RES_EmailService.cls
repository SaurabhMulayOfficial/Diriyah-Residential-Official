/**
 * @description
 * Centralized service responsible for sending prepared email messages in bulk.
 *
 * This service accepts a collection of RES_EmailUtilityService instances,
 * extracts the prepared Messaging.SingleEmailMessage objects, and sends them
 * together through the Salesforce Messaging API.
 *
 * The email preparation logic, including recipients, subject, body, templates,
 * attachments, and other email configurations, is handled by
 * RES_EmailUtilityService.
 *
 * @author Saurabh Mulay
 * @date
 */
public without sharing class RES_EmailService {
    public RES_EmailService() {}

    public static void sendEmail(List<RES_EmailUtilityService> emailUtilityServices) {
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        for (RES_EmailUtilityService emailUtilityService : emailUtilityServices) {
            emailsToSend.add(emailUtilityService.email);
        }

        if (!emailsToSend.isEmpty()) {
            try {
                Messaging.sendEmail(emailsToSend);
            } catch (Exception e) {
                System.debug('Error sending email: ' + e.getMessage());
            }
        }
    }
}
