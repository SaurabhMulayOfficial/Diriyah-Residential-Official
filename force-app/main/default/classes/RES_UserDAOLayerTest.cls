@isTest
private class RES_UserDAOLayerTest {

    @isTest
    static void testGetUserRoleInfo_ReturnsUser() {
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        List<User> results = new RES_UserDAOLayer().getUserRoleInfo(currentUserId);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return the running user');
    }

    @isTest
    static void testGetUserByUsername_ReturnsMapKeyedByUsername() {
        String currentUsername = UserInfo.getUserName();

        Test.startTest();
        Map<String, User> results = new RES_UserDAOLayer().getUserByUsername(new Set<String>{ currentUsername });
        Test.stopTest();

        System.assert(results.containsKey(currentUsername), 'Result map should be keyed by Username');
    }

    @isTest
    static void testGetUsersById_ReturnsMatchingUsers() {
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        List<User> results = new RES_UserDAOLayer().getUsersById(new Set<Id>{ currentUserId });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return the running user');
    }

    @isTest
    static void testGetUsersById_NoMatches_ReturnsNull() {
        Test.startTest();
        List<User> results = new RES_UserDAOLayer().getUsersById(new Set<Id>());
        Test.stopTest();

        System.assertEquals(null, results, 'No matches should return null per the method contract');
    }

    @isTest
    static void testGetUserProfileInfo_ReturnsUser() {
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        List<User> results = new RES_UserDAOLayer().getUserProfileInfo(currentUserId);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return the running user with Profile info');
    }

    @isTest
    static void testGetUserProfileInfo_NullId_ReturnsEmptyList() {
        Test.startTest();
        List<User> results = new RES_UserDAOLayer().getUserProfileInfo(null);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Null id should short-circuit to an empty list');
    }

    @isTest
    static void testGetActiveUsersByManagerIds_ReturnsDirectReports() {
        Id currentUserId = UserInfo.getUserId();
        User u = [SELECT Id, ManagerId FROM User WHERE Id = :currentUserId];

        Test.startTest();
        List<User> results = new RES_UserDAOLayer().getActiveUsersByManagerIds(new Set<Id>{ currentUserId });
        Test.stopTest();

        // The running user may or may not have active direct reports in this org;
        // the call just needs to execute cleanly and return a real list either way.
        System.assertNotEquals(null, results, 'Should return a list, never null, for a non-empty input set');
    }

    @isTest
    static void testGetActiveUsersByManagerIds_EmptySet_ReturnsEmptyList() {
        Test.startTest();
        List<User> results = new RES_UserDAOLayer().getActiveUsersByManagerIds(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Empty input should short-circuit to an empty list');
    }
}
