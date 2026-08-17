/**
 * Class Name: RES_UploadDocumentClass
 * Description: Controller class for uploading, listing, updating, and deleting
 *              Salesforce Files linked to a record.
 */
public with sharing class RES_UploadDocumentClass {
    /**
     * Wrapper used to display file details in LWC.
     */
    public class FileRow {
        /** ContentDocument Id. */
        @AuraEnabled public Id contentDocumentId { get; set; }

        /** ContentVersion Id. */
        @AuraEnabled public Id contentVersionId { get; set; }

        /** File title. */
        @AuraEnabled public String fileName { get; set; }

        /** Editable document label. */
        @AuraEnabled public String documentLabel { get; set; }

        /** Attachment type value. */
        @AuraEnabled public String attachmentType { get; set; }

        /** Created by user name. */
        @AuraEnabled public String createdByName { get; set; }
        
         /** Created Date. */
        @AuraEnabled public String createdDate { get; set; }

        /** Formatted file size. */
        @AuraEnabled public String fileSize { get; set; }

        /** File extension or file type. */
        @AuraEnabled public String fileType { get; set; }
        
        /** Delete Button visibility. */
        @AuraEnabled public Boolean displayDeleteButton { get; set; }
    }

    /**
     * Wrapper used to receive uploaded file metadata from LWC.
     */
    public class UploadFileWrapper {
        /** ContentDocument Id. */
        @AuraEnabled public Id documentId { get; set; }

        /** Uploaded file name. */
        @AuraEnabled public String fileName { get; set; }

        /** Editable document label. */
        @AuraEnabled public String documentLabel { get; set; }

        /** Attachment type value. */
        @AuraEnabled public String attachmentType { get; set; }
    }

  /**
 * Determines whether the current user can edit the document label.
 * Access is granted to:
 * - Users with the System Administrator profile.
 * - Users whose role DeveloperName is included in the allowed roles list.
 *
 * @return true if the current user can edit the document label; otherwise false.
 */
    @AuraEnabled(cacheable=true)
    public static Boolean canEditDocumentLabel() {
        
        RES_ProfileDAOLayer profileDAO = new RES_ProfileDAOLayer();
        String currentUserProfileName = profileDAO.getCurrentUserProfileName();
        
        // System Administrator can always edit
        if (currentUserProfileName == System.Label.RES_Admin_Profile) {
            return true;
        }
        
        Set<String> allowedRoles = new Set<String>{
            'RES_Contract_Amendments_Operations_Specialist',
                'RES_External_Sales_Operations_Operations_Specialist',
                'RES_Internal_Sales_Operations_Operations_Specialist',
                'RES_Operational_Excellence_Operations_Specialist',
                'RES_Sales_DI_Specialist',
                'RES_Sales_DII_Specialist',
                'RES_Sales_External_Specialist',
                'RES_Sales_Implementation_Excellence_Specialist',
                'RES_Sales_Planning_Specialist',
                'RES_Sales_Wadi_Safar_Specialist_I',
                'RES_Sales_Wadi_Safar_Specialist_II',
                'RES_Sales_DI_Relationship_Manager',
                'RES_Sales_External_Relationship_Manager'
                };
                    
                    RES_UserDAOLayer userDAO = new RES_UserDAOLayer();
        List<User> users = userDAO.getUserRoleInfo(UserInfo.getUserId());
        
        if (users.isEmpty() || users[0].UserRole == null) {
            return false;
        }
        
        return allowedRoles.contains(users[0].UserRole.DeveloperName);
    }
    
    /**
     * Returns files linked to the provided record Id.
     *
     * @param recordId parent record Id.
     * @return list of file rows.
     */
    @AuraEnabled
    public static List<FileRow> getFiles(Id recordId) {
        List<FileRow> rows = new List<FileRow>();

        if (recordId == null) {
            return rows;
        }

        List<ContentDocumentLink> links =
            new RES_ContentDocumentLinkDAOLayer().getContentDocumentLinkByLinkedId(recordId);

        Set<Id> versionIds = getLatestVersionIds(links);

        if (versionIds.isEmpty()) {
            return rows;
        }
		RES_ProfileDAOLayer profileDAO = new RES_ProfileDAOLayer();
        String currentUserProfileName = profileDAO.getCurrentUserProfileName();
        Boolean displayDeleteButton = false;
        if (currentUserProfileName == System.Label.RES_Admin_Profile) {
            displayDeleteButton = true;
        }
        List<ContentVersion> cvList =
            new RES_ContentVersionDAOLayer().getContentVersionById(versionIds);

        for (ContentVersion cv : cvList) {
            rows.add(buildFileRow(cv, displayDeleteButton));
        }

        return rows;
    }

    /**
     * Updates uploaded file metadata and links files to the provided record.
     *
     * @param recordId parent record Id.
     * @param files uploaded file wrappers.
     */
    @AuraEnabled
    public static void uploadFiles(Id recordId, List<UploadFileWrapper> files) {
        validateUploadRequest(files);

        Set<Id> documentIds = getDocumentIds(files);
        Map<Id, UploadFileWrapper> fileMap = getFileMap(files);

        updateLatestVersions(documentIds, fileMap);
        createDocumentLinks(recordId, documentIds);
    }

    /**
     * Updates the custom document label on ContentVersion.
     *
     * @param contentVersionId ContentVersion Id.
     * @param documentLabel label value.
     */
    @AuraEnabled
    public static void updateDocumentLabel(Id contentVersionId, String documentLabel) {
        if (contentVersionId == null) {
            throw new AuraHandledException('Content Version Id is missing.');
        }

        if (!Schema.sObjectType.ContentVersion.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update files.');
        }

        update new ContentVersion(
            Id = contentVersionId,
            RES_Document_Label__c = documentLabel
        );
    }

    /**
     * Deletes a Salesforce file by ContentDocument Id.
     *
     * @param contentDocumentId ContentDocument Id.
     */
    @AuraEnabled
    public static void deleteFile(Id contentDocumentId) {
        List<FeedItem> feedItemLst = new List<FeedItem>();
        if (contentDocumentId == null) {
            throw new AuraHandledException('File Id is missing.');
        }

        if (!Schema.sObjectType.ContentDocument.isDeletable()) {
            throw new AuraHandledException('You do not have permission to delete files.');
        }
		
        List<ContentDocumentLink> docLinkLst = new RES_ContentDocumentLinkDAOLayer().getContentDocumentLinkByContentDocumentId(contentDocumentId);
        if(!docLinkLst.isEmpty()){
            for(ContentDocumentLink link : docLinkLst){
                if(!String.valueOf(link.LinkedEntityId).startsWith('005')){
                    FeedItem post = new FeedItem();
                    post.ParentId = link.LinkedEntityId;
                    post.Body = 'The attachment named ' + link.ContentDocument.Title + ' was deleted by ' + UserInfo.getName() + ' at ' + SYSTEM.NOW().format('yyyy-MM-dd h:mm a') + ' ' + UserInfo.getTimeZone().getDisplayName();
                    post.Type = 'TextPost';
                    feedItemLst.add(post);
                }
                
            }
        }
        delete new ContentDocument(Id = contentDocumentId);
        if(!feedItemLst.isEmpty()){
            Database.insert(feedItemLst, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static Set<Id> getLatestVersionIds(List<ContentDocumentLink> links) {
        Set<Id> versionIds = new Set<Id>();

        for (ContentDocumentLink linkRec : links) {
            if (linkRec.ContentDocument.LatestPublishedVersionId != null) {
                versionIds.add(linkRec.ContentDocument.LatestPublishedVersionId);
            }
        }

        return versionIds;
    }

    private static FileRow buildFileRow(ContentVersion cv, Boolean displayDeleteButton) {
        FileRow row = new FileRow();
        row.contentDocumentId = cv.ContentDocumentId;
        row.contentVersionId = cv.Id;
        row.fileName = cv.Title;
        row.documentLabel = String.isBlank(cv.RES_Document_Label__c)
            ? cv.Title
            : cv.RES_Document_Label__c;
        row.attachmentType = cv.RES_Attachment_Type__c;
        row.createdByName = cv.CreatedBy.Name;
        row.createdDate = cv.CreatedDate.format('dd/MM/yyyy, h:mm a');
        row.fileSize = formatFileSize(cv.ContentSize);
        row.fileType = String.isBlank(cv.FileExtension)
            ? cv.FileType
            : cv.FileExtension.toUpperCase();
		row.displayDeleteButton = displayDeleteButton;
        return row;
    }

    private static void validateUploadRequest(List<UploadFileWrapper> files) {
        if (files == null || files.isEmpty()) {
            throw new AuraHandledException('Please select file.');
        }
    }

    private static Set<Id> getDocumentIds(List<UploadFileWrapper> files) {
        Set<Id> documentIds = new Set<Id>();

        for (UploadFileWrapper fileObj : files) {
            if (fileObj != null && fileObj.documentId != null) {
                documentIds.add(fileObj.documentId);
            }
        }

        return documentIds;
    }

    private static Map<Id, UploadFileWrapper> getFileMap(List<UploadFileWrapper> files) {
        Map<Id, UploadFileWrapper> fileMap = new Map<Id, UploadFileWrapper>();

        for (UploadFileWrapper fileObj : files) {
            if (fileObj != null && fileObj.documentId != null) {
                fileMap.put(fileObj.documentId, fileObj);
            }
        }

        return fileMap;
    }

    private static void updateLatestVersions(
        Set<Id> documentIds,
        Map<Id, UploadFileWrapper> fileMap
    ) {
        if (!Schema.sObjectType.ContentVersion.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update files.');
        }

        List<ContentVersion> versionsToUpdate =
            new RES_ContentVersionDAOLayer().getContentVersionToUpdate(documentIds);

        for (ContentVersion cv : versionsToUpdate) {
            UploadFileWrapper wrapper = fileMap.get(cv.ContentDocumentId);

            if (wrapper == null) {
                continue;
            }

            cv.RES_Document_Label__c = wrapper.documentLabel;
            cv.RES_Attachment_Type__c = wrapper.attachmentType;
        }

        try {
            Database.update(versionsToUpdate, false);
        } catch (DmlException ex) {
            throw new AuraHandledException(
                'Error linking files to record: ' + ex.getDmlMessage(0)
            );
        }
    }

    private static void createDocumentLinks(Id recordId, Set<Id> documentIds) {
        if (!Schema.sObjectType.ContentDocumentLink.isCreateable()) {
            throw new AuraHandledException('You do not have permission to link files.');
        }

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();

        for (Id documentId : documentIds) {
            links.add(new ContentDocumentLink(
                ContentDocumentId = documentId,
                LinkedEntityId = recordId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }

        try {
            if (!links.isEmpty()) {
                Database.insert(links, false);
            }
        } catch (DmlException ex) {
            throw new AuraHandledException(
                'Error linking files to record: ' + ex.getDmlMessage(0)
            );
        }
    }

    private static String formatFileSize(Integer size) {
        if (size == null || size == 0) {
            return '0 KB';
        }

        Decimal bytesValue = Decimal.valueOf(size);
        Decimal kb = bytesValue / 1024;
        Decimal mb = kb / 1024;
        Decimal gb = mb / 1024;

        if (gb >= 1) {
            return String.valueOf(gb.setScale(2)) + ' GB';
        }

        if (mb >= 1) {
            return String.valueOf(mb.setScale(2)) + ' MB';
        }

        return String.valueOf(kb.setScale(2)) + ' KB';
    }
}