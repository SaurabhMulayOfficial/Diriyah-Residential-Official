/**
* @ Class Name     	: RES_SendEmailNotificationToGroupMembers
* @ Description    	: This class is used to send email notification to Group Members.
* @ Author			: Nikhil Takawale
*/
public with sharing class RES_SendEmailNotificationToGroupMembers {
    
	@InvocableMethod(label = 'Send Email Notification To Group Members')
    public static void sendEmailNotificationToGroupMembers(List<Input> inputs) {
        if(!inputs.isEmpty()){
            Set<Id> userIdSet = new Set<Id>();
            Contract contractRecord = new Contract();
            String emailTemplateName = '';
            for(Input inputObj : inputs){
                if(inputObj.contractRecord != null){
                    contractRecord = inputObj.contractRecord;
                }
                if(inputObj.emailTemplateName != null){
                    emailTemplateName = inputObj.emailTemplateName;
                }
                if(!inputObj.groupMembers.isEmpty()){
                    for(GroupMember member : inputObj.groupMembers){
                        if(member.UserOrGroupId != null && String.valueOf(member.UserOrGroupId).startsWith('005')){
                            userIdSet.add(member.UserOrGroupId);
                        }
                    }
                }
            }
            if(!userIdSet.isEmpty()){
                List<User> userLst = new RES_UserDAOLayer().getUsersById(userIdSet);
                if(userLst != null){
                    Id orgWideEmailAddressId;
                    List<RES_SendEmailInvocable.inputs> emailLst = new List<RES_SendEmailInvocable.inputs>();
                    List<OrgWideEmailAddress> orgWideAddress = new RES_OrgWideAddressDAO().getOrgWideAddressByDisplayName(System.Label.Org_Wide_Email);
                    if(!orgWideAddress.isEmpty()){
                        orgWideEmailAddressId = orgWideAddress[0].Id;
					}
                    Set<String> apexTemplateNames = new Set<String>{emailTemplateName};
                    Map<String, RES_Apex_Email_Template__mdt> apexTemplates = new RES_ApexEmailTemplateDAO().getApexTemplateByName(apexTemplateNames);
                    if(apexTemplates.size() > 0){
                        RES_Apex_Email_Template__mdt  templateSetting = apexTemplates.get(emailTemplateName);
                        String contractUrl = URL.getOrgDomainUrl().toExternalForm()+ '/' + contractRecord.Id;
                        if(templateSetting != null){
                            for(User userObj : userLst){
                                List<String> mergeFields = new List<String>();
                                RES_SendEmailInvocable.inputs emailInput = new RES_SendEmailInvocable.inputs();
                                emailInput.orgWideEmailAddressId = orgWideEmailAddressId;
                                if(templateSetting.Html_Body__c != null){
                                    emailInput.emailBody = templateSetting.Html_Body__c;
                                }
                                emailInput.emailSubject = templateSetting.Subject__c;
                                emailInput.recipients = new List<String>{userObj.Email};
                                mergeFields.add(userObj.Name);
                                mergeFields.add(contractRecord.ContractNumber);
                                mergeFields.add('signed');
                                mergeFields.add(contractUrl);
                                emailInput.mergeFields = mergeFields;
                                emailLst.add(emailInput);
                            }
                        }
                    }
                    if(!emailLst.isEmpty()){
                        RES_SendEmailInvocable.sendEmails(emailLst);
                    }
                }
            }
		}
    }
    public class Input {
        @InvocableVariable public List<GroupMember> groupMembers;
        @InvocableVariable public Contract contractRecord;
        @InvocableVariable public String emailTemplateName;
    }
}