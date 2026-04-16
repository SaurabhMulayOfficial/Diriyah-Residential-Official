/**
 * Service class for ContentDocument business logic
 * Called from RES_ContentNoteSecurityHandler
 */

public with sharing class RES_ContentNoteServices {
    private static final String NOTE_FILE_TYPE = 'SNOTE';

    public static void preventDelete(final List<ContentDocument> recordsToDelete) {

        if (recordsToDelete.isEmpty() || !isRestrictedProfile()) {
            return;
        }

        for (ContentDocument recordItem : recordsToDelete) {
            if (recordItem.FileType == NOTE_FILE_TYPE) {
                recordItem.addError('You are not allowed to delete Notes.');
            }
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
}