/**
 * @description  Service Class for processing RES_Process_Attachment__e Platform Event.
 * @author       Saurabh Mulay
 * @date         14-Jul-2026
 * @version      1.0
 */

public with sharing class RES_ProcessAttachmentService {

    public static Map<String, String> typeToFieldMapping_contract = new Map<String, String>{
            'Signed URC'             => 'RES_URC_Signed__c',
            'Down Payment Receipt'   => 'RES_Down_Payment_Receipt__c',
            'Simah Form'             => 'RES_SIMAH_Form_Received__c',
            'Payment Plan'           => 'RES_Payment_Plan_Confirmed__c',
            'Signed SPA'             => 'RES_SPA_Signed__c'
        };


    public static void processAttachments(List<RES_Process_Attachment__e> events){
        Map<String, List<RES_Process_Attachment__e>> objectToIds = new Map<String, List<RES_Process_Attachment__e>>();

        for(RES_Process_Attachment__e event: events){
            if(!objectToIds.containsKey(event.RES_Object_Name__c)){
                objectToIds.put(event.RES_Object_Name__c, new List<RES_Process_Attachment__e>());
            }
            objectToIds.get(event.RES_Object_Name__c).add(event);
        }
    
        if(objectToIds.size() <= 0){
            return;
        }

        if(objectToIds.containsKey('Contract')){
            List<RES_Process_Attachment__e> contractEvents = objectToIds.get('Contract');
            
            List<Contract> contractsToUpdate = new List<Contract>();
            for(RES_Process_Attachment__e contractEvent: contractEvents){
                Contract c =processContract(contractEvent);
                if(c != null){
                    contractsToUpdate.add(c);
                }
            }

            try{
                Database.update(contractsToUpdate, false, AccessLevel.SYSTEM_MODE);
            }
            catch(Exception e){
                System.debug('Exception Processing Attachments ' + e.getMessage());
            }
        }
    }

    private static Contract processContract(RES_Process_Attachment__e e){
        Contract c = new Contract(Id = e.RES_recordId__c);
        String action = e.RES_Action__c;
        String attachmentType = e.RES_Attachment_Type__c;
        String fieldApiName = typeToFieldMapping_contract.get(attachmentType);

        if(fieldApiName == null){
            return null;
        }

        if(action == 'Update'){
            c.put(fieldApiName, true);
        }else if(action == 'Delete'){
            c.put(fieldApiName, false);
        }
        return c;
    }
}