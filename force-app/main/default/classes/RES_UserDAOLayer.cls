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

    public Map<String, User> getUserByUsername(Set<String> userNames){
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('userNames', userNames);
        String soql = 'SELECT ID, Username, Email FROM User WHERE Username IN :userNames';
        Map<String, User> userMap = new Map<String, User>();
        List<User> users = (List<User>)executeQuery(soql, 'userByUsername', false, bindVars, AccessLevel.SYSTEM_MODE);
        for(User u : users){
            userMap.put(u.Username, u);
        }
        return userMap;
    }
    
    public List<User> getUsersById(Set<Id> userIdSet){
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('userIdSet', userIdSet);
        String soql = 'SELECT Id, Name, Email ' + 
                      'FROM User ' +
                      'WHERE Id IN : userIdSet';
        Map<String, User> userMap = new Map<String, User>();
        List<User> userLst = (List<User>) executeQuery(soql, 'getUsersById', false, bindVars, AccessLevel.SYSTEM_MODE);
        if(!userLst.isEmpty()){
            return userLst;
        }
        return null;
    }
}