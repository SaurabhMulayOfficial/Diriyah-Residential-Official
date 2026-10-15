/**
 * @description Tests for RES_ProductUpdateConfigDAO. Custom metadata cannot be inserted in a test,
 *              so the records come from the DAO's test hook; the live query path is exercised separately.
 */
@isTest
private class RES_ProductUpdateConfigDAOTest {

    private static RES_Product_Update_Config__mdt cfg(String devName, Boolean active, String status) {
        return new RES_Product_Update_Config__mdt(
            DeveloperName       = devName,
            MasterLabel         = devName,
            RES_Active__c       = active,
            RES_Status_Value__c = status
        );
    }

    @isTest
    static void getActiveConfigs_returnsOnlyActiveRecords() {
        RES_ProductUpdateConfigDAO.mockConfigs = new List<RES_Product_Update_Config__mdt>{
            cfg('Cfg_A', true, 'Available'),
            cfg('Cfg_B', false, 'Soft Hold'),
            cfg('Cfg_C', true, 'Hard Block')
        };

        List<RES_Product_Update_Config__mdt> result = new RES_ProductUpdateConfigDAO().getActiveConfigs();

        Assert.areEqual(2, result.size(), 'Inactive configurations must be left out');
        Assert.areEqual('Cfg_A', result[0].DeveloperName, 'Order of the remaining records is kept');
        Assert.areEqual('Cfg_C', result[1].DeveloperName, 'Order of the remaining records is kept');
    }

    @isTest
    static void getActiveConfigs_noRecords_returnsEmptyListNotNull() {
        RES_ProductUpdateConfigDAO.mockConfigs = new List<RES_Product_Update_Config__mdt>();

        List<RES_Product_Update_Config__mdt> result = new RES_ProductUpdateConfigDAO().getActiveConfigs();

        Assert.isNotNull(result, 'The DAO must never return null');
        Assert.isTrue(result.isEmpty(), 'No records means an empty list');
    }

    @isTest
    static void getActiveConfigs_liveQuery_returnsListWithoutError() {
        RES_ProductUpdateConfigDAO.mockConfigs = null;

        List<RES_Product_Update_Config__mdt> result = new RES_ProductUpdateConfigDAO().getActiveConfigs();

        Assert.isNotNull(result, 'The live query must return a list, even when the org has no records');
        for (RES_Product_Update_Config__mdt c : result) {
            Assert.areEqual(true, c.RES_Active__c, 'Only active configurations are queried');
        }
    }

    @isTest
    static void getConfigByDeveloperName_blankName_returnsNull() {
        RES_ProductUpdateConfigDAO dao = new RES_ProductUpdateConfigDAO();
        Assert.isNull(dao.getConfigByDeveloperName(null), 'Null name must return null');
        Assert.isNull(dao.getConfigByDeveloperName('   '), 'Blank name must return null');
    }

    @isTest
    static void getConfigByDeveloperName_found_returnsMatchingRecord() {
        RES_ProductUpdateConfigDAO.mockConfigs = new List<RES_Product_Update_Config__mdt>{
            cfg('Cfg_A', true, 'Available'),
            cfg('Cfg_B', false, 'Soft Hold')
        };

        RES_Product_Update_Config__mdt result = new RES_ProductUpdateConfigDAO().getConfigByDeveloperName('Cfg_B');

        Assert.isNotNull(result, 'A record with that developer name exists');
        Assert.areEqual('Soft Hold', result.RES_Status_Value__c, 'The matching record is returned, active or not');
    }

    @isTest
    static void getConfigByDeveloperName_notFound_returnsNull() {
        RES_ProductUpdateConfigDAO.mockConfigs = new List<RES_Product_Update_Config__mdt>{ cfg('Cfg_A', true, 'Available') };

        Assert.isNull(new RES_ProductUpdateConfigDAO().getConfigByDeveloperName('Missing'),
            'An unknown developer name returns null');
    }

    @isTest
    static void getConfigByDeveloperName_liveQuery_unknownNameReturnsNull() {
        RES_ProductUpdateConfigDAO.mockConfigs = null;

        Assert.isNull(new RES_ProductUpdateConfigDAO().getConfigByDeveloperName('No_Such_Config_Record'),
            'The live query finds nothing for an unknown name and returns null');
    }
}
