/**
* @ Class Name     	: RES_SLAExpiredApprovalItemsReminder
* @ Description    	: Invoked via RES_SLA_Expired_Approval_Work_Items_Send_Daily_Reminder Flow
					  to send reminder emails to respective public groups assigned to the
					  SLA Expired Approval Work Items
* @ Author			: Nikhil Takawale
*/
public with sharing class RES_SLAExpiredApprovalItemsReminder {
    public static final Set<String> publicGroupDeveloperNames = new Set<String>{'RES_Sales_Ops_Executive_Director_Group', 'RES_Finance_Team_Group', 'RES_Chief_Business_Development_Officer'};
	public static final String emailTemplateName = 'RES_Approval_Work_Item_Pending_Approval';
    @InvocableMethod(label = 'Send Daily Reminders To SLA Expired Approval Work Items')
    public static void sendDailyRemindersToSLAExpiredApprovalWorkItems(List<Input> inputs){
        if(!inputs.isEmpty()){
            Input inputObj = inputs[0];
            if(!inputObj.approvalWorkItemsLst.isEmpty()){
                Set<Id> contractIdSet = new Set<Id>();
                Map<Id, String> contractIdToContractNumberMap = new Map<Id, String>();
                Map<Id, String> groupsMap = new RES_GroupDAOLayer().getGroupsByDeveloperNames(publicGroupDeveloperNames);
                Map<String, Set<String>> groupRecipientsEmailMap = new RES_GroupMemberDAOLayer().getGroupMembersByGroupNames(publicGroupDeveloperNames);
                Map<String, String> teamNamesMap = new Map<String, String>{
                    	'RES_Sales_Ops_Executive_Director_Group' => 'Sales Operations Team',
                        'RES_Finance_Team_Group' => 'Finance Team',
                        'RES_Chief_Business_Development_Officer' => 'CBDO Team'
                };
                Id orgWideEmailId = new RES_OrgWideAddressDAO().getOrgWideAddressByDisplayName(System.Label.Org_Wide_Email)[0].Id;
                Map<String,RES_Apex_Email_Template__mdt> emailTemplateMap = new RES_ApexEmailTemplateDAO().getApexTemplateByName(new Set<String>{emailTemplateName});
                for(ApprovalWorkItem workItem : inputObj.approvalWorkItemsLst){
                    contractIdSet.add(workItem.RelatedRecordId);
                }
                if(!contractIdSet.isEmpty()){
                	Map<Id, Contract> contractsMap = new Map<Id, Contract>(new RES_ContractDAOLayer().getContractsByIds(contractIdSet));
                    if(contractsMap.size() > 0){
                    	for(ApprovalWorkItem workItem : inputObj.approvalWorkItemsLst){
                        	String teamName = teamNamesMap.get(groupsMap.get(workItem.AssignedToId));
                            String contractNumber = contractsMap.get(workItem.RelatedRecordId).ContractNumber;
                            String slaEndDate = getSLAEndDate(workItem.RES_SLA_End_Date__c);
                            String contractURL = getRecordUrl(workItem.RelatedRecordId);
                            String approvalWorkItemURL = getRecordUrl(workItem.Id);
                            List<String> mergeFields = populateMergeFields(teamName, workItem.Name, contractNumber, slaEndDate, workItem.Status, contractURL, approvalWorkItemURL);
                            List<RES_SendEmailInvocable.inputs> inputLst = new List<RES_SendEmailInvocable.inputs>();
                            RES_SendEmailInvocable.inputs input = new RES_SendEmailInvocable.inputs();
                            input.orgWideEmailAddressId = orgWideEmailId;
                            input.emailBody = emailTemplateMap.get(emailTemplateName).Html_Body__c;
        					input.emailSubject = emailTemplateMap.get(emailTemplateName).Subject__c;
        					input.recipients = new List<String>(groupRecipientsEmailMap.get(groupsMap.get(workItem.AssignedToId)));
        					input.mergeFields = mergeFields;
                            inputLst.add(input);
                            RES_SendEmailInvocable.sendEmails(inputLst);
                    	}
                	}
            	}
            }
        }
    }
    
    private static List<String> populateMergeFields(String teamName, String approvalWorkItemName, String contractNumber, String slaEndDate, String approvalWorkItemStatus, String contractURL, String approvalWorkItemURL){
        List<String> mergeFields = new List<String>();
        mergeFields.add(teamName);
        mergeFields.add(approvalWorkItemName);
        mergeFields.add(contractNumber);
        mergeFields.add(slaEndDate);
        mergeFields.add(approvalWorkItemStatus);
        mergeFields.add(contractURL);
        mergeFields.add(approvalWorkItemURL);
        return mergeFields;
    }
    
    private static String getSLAEndDate(Datetime slaEndDate){
        return slaEndDate.format('dd-MMM-yyyy \'at\' h:mm a');
    }
    
    private static String getRecordUrl(Id recordId) {
        return URL.getOrgDomainUrl().toExternalForm() + '/' + recordId;
    }

    public class Input {
        @InvocableVariable public List<ApprovalWorkItem> approvalWorkItemsLst;
    }
}