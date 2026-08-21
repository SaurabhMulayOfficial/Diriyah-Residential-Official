/**
 * Class Name   : RES_ProcessInstanceDAOLayer
 * Description  : Data Access Object (DAO) layer for the ApprovalWorkItem object.
 *                Provides standardized methods for querying and retrieving
 *                ApprovalWorkItem records within the application.
 *
 * Framework Rule:
 *      - All DAO layers must extend RES_BaseDAOLayer.
 *      - Each implementation must override getSObjectName()
 *        to specify the associated SObject.
 */

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
 *    To get Map<id, Sobject> use executeQueryToMap(<Same Params as above>).
 * 
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
public without sharing class RES_ProcessInstanceDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ApprovalWorkItem';
    }

    public List<ApprovalWorkItem> getPendingWorkItemsByTargetIds(Set<Id> targetIds, String relatedObjectName) {
        if (targetIds == null || targetIds.isEmpty()) {
            return new List<ApprovalWorkItem>();
        }
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('targetIds', targetIds);
        bindVars.put('relatedObjectName', relatedObjectName);
        String soql = 'SELECT Id, Status, RelatedRecordObjectName, RelatedRecordId, ApprovalSubmissionId ' +
                        'FROM ApprovalWorkItem ' +
                        'WHERE RelatedRecordId IN :targetIds ' +
                        'AND RelatedRecordObjectName = :relatedObjectName ' +
                        'AND Status = \'Assigned\'';
        return (List<ApprovalWorkItem>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public List<ProcessInstance> getApprovalHistoryByTargetIds(Set<Id> targetIds) {
        if (targetIds == null || targetIds.isEmpty()) return new List<ProcessInstance>();
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('targetIds', targetIds);
        String soql = 'SELECT Id, TargetObjectId, ' +
                        '(SELECT Comments FROM StepsAndWorkitems ORDER BY CreatedDate DESC LIMIT 1) ' +
                        'FROM ProcessInstance WHERE TargetObjectId IN :targetIds ORDER BY CreatedDate DESC';
        return (List<ProcessInstance>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
    
    public List<ApprovalWorkItem> getApprovalWorkItems(
        Set<Id> relatedToIds,
        String assignedToName
    ) {
        if (relatedToIds == null || relatedToIds.isEmpty()) {
            return new List<ApprovalWorkItem>();
        }

        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('relatedToIds', relatedToIds);
        bindVars.put('assignedToName', assignedToName);

        String soql =
            'SELECT Id, AssignedTo.Name, ApprovalSubmissionId, Status, RelatedRecordId ' +
            'FROM ApprovalWorkItem ' +
            'WHERE AssignedTo.Name = :assignedToName ' +
            'AND Status = \'Assigned\' ' +
            'AND RelatedRecordId IN :relatedToIds ' +
            'ORDER BY CreatedDate DESC';

        return (List<ApprovalWorkItem>) executeQuery(
            soql,
            '',
            false,
            bindVars,
            AccessLevel.SYSTEM_MODE
        );
    }
}