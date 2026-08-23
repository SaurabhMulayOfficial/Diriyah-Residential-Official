public with sharing class RES_ErrorLogger {

    public static void log(String classAndMethod, Exception ex, Id relatedRecordId) {
        log(classAndMethod, ex.getMessage() + ' | ' + ex.getStackTraceString(), relatedRecordId);
    }
    
    public static void log(String classAndMethod, String message, Id relatedRecordId) {
        try {
            if (Schema.sObjectType.RES_Integration_Log__c.isCreateable()) {
                RES_Integration_Log__c logEntry = new RES_Integration_Log__c(
                    RES_Class_Method__c = classAndMethod,
                    RES_Error_Message__c = message,
                    RES_Record_Id__c = (relatedRecordId != null ? String.valueOf(relatedRecordId) : null)
                );
                Database.insert(logEntry, AccessLevel.USER_MODE);
            }
        } catch (Exception loggingEx) {
            System.debug(LoggingLevel.ERROR, 'RES_ErrorLogger failed: ' + loggingEx.getMessage());
        }
    }
}