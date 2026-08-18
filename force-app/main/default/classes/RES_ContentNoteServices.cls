/**
 * Service class for ContentDocument business logic
 * Called from RES_ContentNoteSecurityHandler
 */

public with sharing class RES_ContentNoteServices {
    //private static final String NOTE_FILE_TYPE = 'SNOTE';

    public static void preventDelete(final List<ContentDocument> recordsToDelete) {

        if (recordsToDelete.isEmpty() || !isRestrictedProfile()) {
            publishPlatformEvents(recordsToDelete);
            return;
        }

        for (ContentDocument recordItem : recordsToDelete) {
            //if (recordItem.FileType == NOTE_FILE_TYPE) {
                recordItem.addError('You are not allowed to perform this action.');
            //}
        }
    }

    private static Boolean isRestrictedProfile() {
        String currentProfileName = new RES_ProfileDAOLayer().getCurrentUserProfileName();
        for (RES_Note_Delete_Restriction__mdt config :
            RES_Note_Delete_Restriction__mdt.getAll().values()) {
            if (config.RES_Profile_Name__c == currentProfileName) {
                return true;
            }
        }
        return false;
    }
    
    private static void publishPlatformEvents(List<ContentDocument> recordsToDelete) {
        if(!recordsToDelete.isEmpty()){
            Set<Id> documentIds = new Set<Id>();
            for(ContentDocument cdObj : recordsToDelete){
                documentIds.add(cdObj.Id);
            }
            if(!documentIds.isEmpty()){
                List<ContentVersion> versionLst = new RES_ContentVersionDAOLayer().getContentVersionToUpdate(documentIds);
                List<ContentDocumentLink> docLinkLst = new RES_ContentDocumentLinkDAOLayer().getContentDocumentLinkByContentDocumentId(documentIds);
                Map<Id, String> contentDocMap = new Map<Id, String>();
                List<FeedItem> feedItemLst = new List<FeedItem>();
                List<RES_Process_Attachment__e> eventLst = new List<RES_Process_Attachment__e>();
                if(!versionLst.isEmpty()){
                    for(ContentVersion cvObj : versionLst){
                        if(!contentDocMap.containsKey(cvObj.ContentDocumentId)){
                            contentDocMap.put(cvObj.ContentDocumentId, cvObj.RES_Attachment_Type__c);
                        }
                    }
                }
                if(!docLinkLst.isEmpty()){
                    for(ContentDocumentLink link : docLinkLst){
                        if(!String.valueOf(link.LinkedEntityId).startsWith('005')){
                            RES_Process_Attachment__e event = new RES_Process_Attachment__e(
                                RES_Action__c = 'Delete',
                                RES_Attachment_Type__c = contentDocMap.get(link.ContentDocumentId),
                                RES_Object_Name__c = link.LinkedEntityId.getSObjectType().getDescribe().getName(),
                                RES_recordId__c = link.LinkedEntityId
                            );
                            eventLst.add(event);
                            
                            FeedItem post = new FeedItem();
                            post.ParentId = link.LinkedEntityId;
                            post.Body = 'The attachment named ' + link.ContentDocument.Title + ' was deleted by ' + UserInfo.getName() + ' at ' + SYSTEM.NOW().format('yyyy-MM-dd h:mm a') + ' ' + UserInfo.getTimeZone().getDisplayName();
                            post.Type = 'TextPost';
                            feedItemLst.add(post);
                        }
                    }
                }
                if(!eventLst.isEmpty()){
                    EventBus.publish(eventLst);
                }
                if(!feedItemLst.isEmpty()){
                    Database.insert(feedItemLst, false, AccessLevel.SYSTEM_MODE);
                }
            }
        }
    }
}