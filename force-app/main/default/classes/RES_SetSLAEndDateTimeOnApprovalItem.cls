/**
 * Class Name: RES_SetSLAEndDateTimeOnApprovalWorkItem
 * Description: Class for calculating RES_SLA_End_Date__c field on the ApprovalWorkItem.
 */

public with sharing class RES_SetSLAEndDateTimeOnApprovalItem {
    
    @InvocableMethod(label = 'Set SLA End Date Time On Approval Work Item')
    public static List<Output> setSLAEndDateTimeOnApprovalWorkItem(List<Input> inputs) {
        List<Output> outputLst = new List<Output>();
        if(!inputs.isEmpty()){
            List<BusinessHours> businessHoursLst = new RES_BusinessHoursDAOLayer().getDefaultBusinessHours();
            if(!businessHoursLst.isEmpty()){
                BusinessHours bhObj = businessHoursLst[0];
                for(Input inputObj : inputs){
                    if(inputObj.numberOfBusinessDays != NULL && inputObj.businessHours != NULL){
                        Output outputObj = new Output();
                        outputObj.slaEndDate = BusinessHours.add(bhObj.Id, SYSTEM.NOW(), (inputObj.numberOfBusinessDays * inputObj.businessHours) * 60 * 60 * 1000L);
                    	outputLst.add(outputObj);
                    }
                }
            }
        }
        return outputLst;
    }
    
    public class Input {
        @InvocableVariable public Integer numberOfBusinessDays;
        @InvocableVariable public Integer businessHours;
    }
    
    public class Output {
        @InvocableVariable public Datetime slaEndDate;
    }
    
}