/**
 * @description  Service Class for processing RES_Process_Attachment__e Platform Event.
 * @author       Saurabh Mulay
 * @date         14-Jul-2026
 * @version      1.0
 */

public with sharing class RES_ProcessAttachmentService {

    public static Map<String, Map<String, String>> objectToFieldMappings = new Map<String, Map<String, String>>();
    
    public static void hydrateMappings(){
        List<RES_Attachment_Type_To_Field_Mapping__mdt> mappings = new RES_ActtachmentTypeToFieldMappingDAO().getAllMappings();
        for(RES_Attachment_Type_To_Field_Mapping__mdt mapping: mappings){
            String objectName = mapping.RES_Object_Name__c;
            String jsonMapping = mapping.RES_JsonMapping__c;

            if(objectToFieldMappings.containsKey(objectName)){
                continue;
            }
            
            Map<String, Object> tempMap =(Map<String, Object>)JSON.deserializeUntyped(mapping.RES_JsonMapping__c);
            Map<String, String> fieldMap = new Map<String, String>();
            for (String key : tempMap.keySet()) {
                fieldMap.put(key, (String)tempMap.get(key));
            }

            objectToFieldMappings.put(objectName, fieldMap);
        }
    }

    public static void processAttachments(List<RES_Process_Attachment__e> events){
        hydrateMappings();

        List<SObject> recordsToUpdate = new List<SObject>();

        if(objectToFieldMappings.size() <= 0){
            return;
        }

        for(RES_Process_Attachment__e e: events){
            SObject record =processSObject(e);
            if(record != null){
                recordsToUpdate.add(record);
            }
        }

        try{
            Database.update(recordsToUpdate, false, AccessLevel.SYSTEM_MODE);
        }
        catch(DmlException e){
            System.debug('Error updating records: ' + e.getMessage());
        }
    }

    private static SObject processSObject(RES_Process_Attachment__e e){
        String objectName = e.RES_Object_Name__c;
        if(objectName == 'PersonAccount' || objectName == 'CompanyAccount'){
            objectName = 'Account';
        }
        String recordId = e.RES_recordId__c;
        String attachmentType = e.RES_Attachment_Type__c;
        String action = e.RES_Action__c;

        if(!objectToFieldMappings.containsKey(objectName)){
            return null;
        }

        Map<String, String> fieldMappings = objectToFieldMappings.get(objectName);

        if(!fieldMappings.containsKey(attachmentType)){
            return null;
        }

        String fieldAPIName = (String)fieldMappings.get(attachmentType);
        
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
        SObject record = sObjectType.newSObject();
        record.Id = recordId;
        if(action == 'Delete'){
            record.put(fieldAPIName, false);
        }else if(action == 'Update'){
            record.put(fieldAPIName, true);
        }

        return record;
    }
}