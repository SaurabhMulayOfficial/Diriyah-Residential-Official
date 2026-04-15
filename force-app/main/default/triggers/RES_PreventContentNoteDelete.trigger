/**
 * Trigger Name   : RES_PreventContentNoteDelete
 * Description    : Delete access on Notes restricted for users with Diriyah Sales profile.
 *                  RES_ContentNoteSecurityHandler handles preventDelete method
 */
trigger RES_PreventContentNoteDelete on ContentDocument (before delete) {
    //RES_ContentNoteSecurityHandler.preventDelete(Trigger.old);//Nikhil commented old logic
    new RES_ContentNoteSecurityHandler().run(); //Nikhil new logic
}