/**
 * Class Name     : RES_ContentNoteSecurityHandler
 * Description    : Delete access on Notes restricted for users with Diriyah Sales profile.
 *                  preventDelete method handles delete restriction.
 */
public with sharing class RES_ContentNoteSecurityHandler extends RES_BaseTriggerHandler{
    protected override void beforeDelete() {
        RES_ContentNoteServices.preventDelete((List<ContentDocument>)Trigger.old);
    }
}