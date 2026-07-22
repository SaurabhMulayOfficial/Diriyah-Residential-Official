/**
 * =============================================================================
 * QUERY EXECUTION GUIDELINES
 * =============================================================================
 *
 * 1. Standard Query Execution
 *    Method:
 *      executeQuery(String soql,
 *                   String cacheSuffix,
 *                   Boolean useCache,
 *                   Map<String, Object> bindVars,
 *                   AccessLevel accessLevel)
 *    Usage Guidelines:
 *      - Enable caching ONLY for static queries where data does not change frequently.
 *      - For dynamic queries:
 *            • Set useCache = false
 *            • Set cacheSuffix = ''
 *
 * 2. Batch Query Execution
 *    Method:
 *      executeBatchQuery(String soql,
 *                        Map<String, Object> bindVars,
 *                        AccessLevel accessLevel)
 * =============================================================================
 */

public without sharing class RES_ApexEmailTemplateDAO extends RES_BaseDAOLayer {
    public RES_ApexEmailTemplateDAO() {}

    protected override String getSObjectName() {
        return 'RES_Apex_Email_Template__mdt';
    }

    public Map<String,RES_Apex_Email_Template__mdt> getApexTemplateByName(Set<String> apexTemplateNames){
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('apexTemplateNames', apexTemplateNames);
        String soql = 'SELECT DeveloperName, Html_Body__c, Subject__c FROM RES_Apex_Email_Template__mdt WHERE DeveloperName IN :apexTemplateNames';
        List<RES_Apex_Email_Template__mdt> apexTemplates = executeQuery(soql, 'ApexTemplateByName', true, bindVars, AccessLevel.SYSTEM_MODE);
        Map<String, RES_Apex_Email_Template__mdt> result = new Map<String, RES_Apex_Email_Template__mdt>();

        for(RES_Apex_Email_Template__mdt template : apexTemplates){
            result.put(template.developerName, template);
        }
        return result;
    }
}