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


public with sharing class RES_GroupMemberDAOLayer extends RES_BaseDAOLayer{
    public RES_GroupMemberDAOLayer() {}

    protected override String getSObjectName() {
        return 'GroupMember';
    }

    public Map<Id, Set<Id>> getGroupMembersByIds(Set<id> groupIds){
        Map<Id, Set<Id>> groupToUsersMapping = new Map<Id, Set<Id>>();

        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('groupIds', groupIds);

        String soql = 'SELECT UserOrGroupId,GroupId From GroupMember WHERE GroupId IN: groupIds';
        List<GroupMember> grpMemberList = (List<GroupMember>) executeQuery(soql, 'GroupMemberById', true, bindVars, AccessLevel.SYSTEM_MODE);

        for(GroupMember M: grpMemberList){
            if(groupToUsersMapping.containsKey(M.GroupId)){
                groupToUsersMapping.get(M.GroupId).add(M.UserOrGroupId);
            }else{
                groupToUsersMapping.put(M.GroupId, new Set<Id>{M.UserOrGroupId});
            }
        }

        return groupToUsersMapping;

    }

}