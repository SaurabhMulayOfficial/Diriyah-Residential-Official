/**
 * @description  Service Class for handling RES_File_Type__mdt records.
 * @author       Saurabh Mulay
 * @date         14-Jul-2026
 * @version      1.0
 */
public with sharing class RES_FileTypeMdtService {
    public RES_FileTypeMdtService() {}

    @AuraEnabled(Cacheable=true)
    public static List<String> getFileTypes(String ObjectName){
        try {
            List<RES_File_Type__mdt> fileTypes = new RES_FileTypeMdtDAO().getFileTypesByObjectName(ObjectName);
            List<String> fileTypeNames = new List<String>();
            if(fileTypes != null && !fileTypes.isEmpty()) {
                fileTypeNames = fileTypes[0].RES_File_Types__c.split(',');
            }
            return fileTypeNames;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(Cacheable=true)
    public static String findObjectNameFromRecordIdPrefix(String recordIdOrPrefix) {
        String objectName = '';
        try {
            String myIdPrefix = String.valueOf(recordIdOrPrefix).substring(0, 3);
            Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
            for (Schema.SObjectType stype : gd.values()) {
                Schema.DescribeSObjectResult r = stype.getDescribe();
                String prefix = r.getKeyPrefix();
                if (prefix != null && prefix.equals(myIdPrefix)) {
                    objectName = r.getName();
                    break;
                }
            }
        } catch (Exception e) {
            System.debug(e);
        }
        return objectName;
    }

    @AuraEnabled
    public static void publishProcessAttachmentEvent(String objectName, String recordId, String action, String attachmentType){
        try {
            RES_Process_Attachment__e event = new RES_Process_Attachment__e(
                RES_Action__c = action,
                RES_Attachment_Type__c = attachmentType,
                RES_Object_Name__c = objectName,
                RES_recordId__c = recordId
            );

            EventBus.publish(event);
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}