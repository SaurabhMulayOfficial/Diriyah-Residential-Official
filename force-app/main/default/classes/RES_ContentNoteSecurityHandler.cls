/**
 * Class Name     : RES_ContentNoteSecurityHandler
 * Description    : Delete access on Notes restricted for users with Diriyah Sales profile.
 *                  preventDelete method handles delete restriction.
 */
public with sharing class RES_ContentNoteSecurityHandler extends RES_BaseTriggerHandler{
    //Nikhil commented old logic
    /*private static final String NOTE_FILE_TYPE = 'SNOTE';

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
        String currentProfileName = [
            SELECT Name
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
            LIMIT 1
        ].Name;

        for (RES_Note_Delete_Restriction__mdt config :
            RES_Note_Delete_Restriction__mdt.getAll().values()) {

            if (config.RES_Profile_Name__c == currentProfileName) {
                return true;
            }
        }
        return false;
    }*/

    //Nikhil new logic
    protected override void beforeDelete() {
        RES_ContentNoteServices.preventDelete((List<ContentDocument>)Trigger.old);
    }
}