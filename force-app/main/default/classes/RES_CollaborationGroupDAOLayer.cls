/**
 * Class Name   : RES_CollaborationGroupDAOLayer
 * Description  : Data Access Object (DAO) layer for the CollaborationGroup (Chatter group) object.
 */
public without sharing class RES_CollaborationGroupDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'CollaborationGroup';
    }

    /**
     * Returns the Chatter groups with the given names.
     *
     * @param groupNames Set of Chatter group names.
     * @return list of CollaborationGroup records.
     */
    public List<CollaborationGroup> getGroupsByNames(Set<String> groupNames) {
        if (groupNames == null || groupNames.isEmpty()) {
            return new List<CollaborationGroup>();
        }
        Map<String, Object> bindVars = new Map<String, Object>{ 'groupNames' => groupNames };
        String soql = 'SELECT Id, Name FROM CollaborationGroup WHERE Name IN :groupNames';
        return (List<CollaborationGroup>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}