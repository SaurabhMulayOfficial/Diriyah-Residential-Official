/**
 * Class Name: RES_SetSLAEndDateTimeOnApprovalWorkItem
 * Description: Class for calculating RES_SLA_End_Date__c field on the ApprovalWorkItem.
 */

public with sharing class RES_SetSLAEndDateTimeOnApprovalItem {
    
    @InvocableMethod(label = 'Set SLA End Date Time On Approval Work Item')
    public static void setSLAEndDateTimeOnApprovalWorkItem(List<Input> inputs) {
        if(!inputs.isEmpty()){
            List<BusinessHours> businessHoursLst = new RES_BusinessHoursDAOLayer().getDefaultBusinessHours();
            List<ApprovalWorkItem> approvalWorkItemLstUpdate = new List<ApprovalWorkItem>();
            if(!businessHoursLst.isEmpty()){
                BusinessHours bhObj = businessHoursLst[0];
                for(Input inputObj : inputs){
                    if(inputObj.approvalWorkItemRecord != NULL && inputObj.numberOfBusinessDays != NULL && inputObj.businessHours != NULL){
                        ApprovalWorkItem workItem = new ApprovalWorkItem(Id = inputObj.approvalWorkItemRecord.Id, RES_SLA_End_Date__c = BusinessHours.add(bhObj.Id, SYSTEM.NOW(), (inputObj.numberOfBusinessDays * inputObj.businessHours) * 60 * 60 * 1000L));
                        approvalWorkItemLstUpdate.add(workItem);
                    }
                }
                if(!approvalWorkItemLstUpdate.isEmpty()){
                    Database.update(approvalWorkItemLstUpdate, false, AccessLevel.SYSTEM_MODE);
                }
            }
        }
    }
    
    public class Input {
        @InvocableVariable public ApprovalWorkItem approvalWorkItemRecord;
        @InvocableVariable public Integer numberOfBusinessDays;
        @InvocableVariable public Integer businessHours;
    }
    
}