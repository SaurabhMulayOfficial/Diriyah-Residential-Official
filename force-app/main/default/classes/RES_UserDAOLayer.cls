/**
 * Class Name   : RES_UserDAOLayer
 * Description  : Data Access Object (DAO) layer for the User object.
 * * Framework Rule:
 * - All DAO layers must extend RES_BaseDAOLayer.
 * - Each implementation must override getSObjectName().
 */
public with sharing class RES_UserDAOLayer extends RES_BaseDAOLayer {

    protected override String getSObjectName() {
        return 'User';
    }

    /**
     * @description Retrieves User and Role information for the current user.
     * @param userId The ID of the user to query.
     * @return List<User> containing UserRole information.
     */
    public List<User> getUserRoleInfo(Id userId) {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('userId', userId);
        
        String soql = 'SELECT UserRole.DeveloperName FROM User WHERE Id = :userId LIMIT 1';
        
        // We set useCache to false for dynamic user session data
        return (List<User>) executeQuery(soql, 'currentUserRole', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}