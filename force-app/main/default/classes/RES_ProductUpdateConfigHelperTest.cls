/**
 * @description Tests for RES_ProductUpdateConfigHelper: configuration lookup by status, custom label lookup,
 *              and the defaults applied when a metadata record leaves a value empty.
 */
@isTest
private class RES_ProductUpdateConfigHelperTest {

    private static final List<String> KNOWN_LABELS = new List<String>{
        'RES_Product_Update_Warning_Active', 'RES_Product_Update_Warning_Hold', 'RES_Product_Update_Success',
        'RES_Product_Update_Comments_Required', 'RES_Product_Update_Comments_Min_Length',
        'RES_Product_Update_Error_Generic', 'RES_Product_Update_Status_Active_Info',
        'RES_Product_Update_Status_Hold_Info', 'RES_Product_Update_Modal_Title', 'RES_Product_Update_Confirm_Title'
    };

    private static void useConfigs(List<RES_Product_Update_Config__mdt> configs) {
        RES_ProductUpdateConfigDAO.mockConfigs = configs;
    }

    private static RES_Product_Update_Config__mdt fullConfig() {
        return new RES_Product_Update_Config__mdt(
            DeveloperName            = 'Full',
            RES_Active__c            = true,
            RES_Status_Value__c      = 'Available',
            RES_Warning_Label__c     = 'RES_Product_Update_Warning_Active',
            RES_Requires_Warning__c  = true,
            RES_Target_Status__c     = 'Draft',
            RES_Min_Comment_Length__c = 25
        );
    }

    private static RES_Product_Update_Config__mdt sparseConfig() {
        return new RES_Product_Update_Config__mdt(
            DeveloperName       = 'Sparse',
            RES_Active__c       = true,
            RES_Status_Value__c = 'Soft Hold'
        );
    }

    // ── getAllConfigs ────────────────────────────────────────────────────────

    @isTest
    static void getAllConfigs_noActiveRecords_returnsEmptyMap() {
        useConfigs(new List<RES_Product_Update_Config__mdt>());

        Map<String, RES_ProductUpdateConfigHelper.ProductUpdateConfig> result = RES_ProductUpdateConfigHelper.getAllConfigs();

        Assert.isNotNull(result, 'The map is never null');
        Assert.isTrue(result.isEmpty(), 'No active records gives an empty map');
    }

    @isTest
    static void getAllConfigs_mapsEveryFieldFromTheRecord() {
        useConfigs(new List<RES_Product_Update_Config__mdt>{ fullConfig() });

        RES_ProductUpdateConfigHelper.ProductUpdateConfig c = RES_ProductUpdateConfigHelper.getAllConfigs().get('Available');

        Assert.isNotNull(c, 'The record is keyed by its status value');
        Assert.areEqual('Available', c.statusValue, 'statusValue');
        Assert.areEqual('RES_Product_Update_Warning_Active', c.warningLabelName, 'warningLabelName');
        Assert.areEqual(true, c.requiresWarning, 'requiresWarning');
        Assert.areEqual('Draft', c.targetStatus, 'targetStatus');
        Assert.areEqual(25, c.minCommentLength, 'minCommentLength is read from the record');
        Assert.areEqual(System.Label.RES_Product_Update_Warning_Active, c.warningMessage,
            'The warning message is the text of the named custom label');
    }

    @isTest
    static void getAllConfigs_emptyValues_useDefaults() {
        useConfigs(new List<RES_Product_Update_Config__mdt>{ sparseConfig() });

        RES_ProductUpdateConfigHelper.ProductUpdateConfig c = RES_ProductUpdateConfigHelper.getAllConfigs().get('Soft Hold');

        Assert.areEqual(false, c.requiresWarning, 'A missing flag means no warning');
        Assert.areEqual(10, c.minCommentLength, 'A missing minimum length defaults to 10');
        Assert.areEqual('', c.warningMessage, 'No label name gives an empty message');
    }

    @isTest
    static void getAllConfigs_skipsRecordsWithoutStatusValue() {
        RES_Product_Update_Config__mdt noStatus = new RES_Product_Update_Config__mdt(
            DeveloperName = 'NoStatus', RES_Active__c = true);
        useConfigs(new List<RES_Product_Update_Config__mdt>{ noStatus, fullConfig() });

        Map<String, RES_ProductUpdateConfigHelper.ProductUpdateConfig> result = RES_ProductUpdateConfigHelper.getAllConfigs();

        Assert.areEqual(1, result.size(), 'A record without a status value cannot be keyed and is skipped');
        Assert.isTrue(result.containsKey('Available'), 'The valid record is kept');
    }

    // ── getConfigForStatus ───────────────────────────────────────────────────

    @isTest
    static void getConfigForStatus_blankStatus_returnsNull() {
        useConfigs(new List<RES_Product_Update_Config__mdt>{ fullConfig() });

        Assert.isNull(RES_ProductUpdateConfigHelper.getConfigForStatus(null), 'Null status returns null');
        Assert.isNull(RES_ProductUpdateConfigHelper.getConfigForStatus(''), 'Blank status returns null');
    }

    @isTest
    static void getConfigForStatus_known_returnsConfig() {
        useConfigs(new List<RES_Product_Update_Config__mdt>{ fullConfig(), sparseConfig() });

        RES_ProductUpdateConfigHelper.ProductUpdateConfig c = RES_ProductUpdateConfigHelper.getConfigForStatus('Soft Hold');

        Assert.isNotNull(c, 'A configured status returns its configuration');
        Assert.areEqual('Soft Hold', c.statusValue, 'The matching configuration is returned');
    }

    @isTest
    static void getConfigForStatus_unknownStatus_returnsNull() {
        useConfigs(new List<RES_Product_Update_Config__mdt>{ fullConfig() });

        Assert.isNull(RES_ProductUpdateConfigHelper.getConfigForStatus('Sold'), 'A status without a configuration returns null');
    }

    @isTest
    static void getConfigForStatus_noConfigurationsAtAll_returnsNull() {
        useConfigs(new List<RES_Product_Update_Config__mdt>());

        Assert.isNull(RES_ProductUpdateConfigHelper.getConfigForStatus('Available'), 'With nothing configured the result is null');
    }

    // ── getLabel / getAllLabels ──────────────────────────────────────────────

    @isTest
    static void getLabel_blank_returnsEmptyString() {
        Assert.areEqual('', RES_ProductUpdateConfigHelper.getLabel(null), 'Null label name gives an empty string');
        Assert.areEqual('', RES_ProductUpdateConfigHelper.getLabel(''), 'Blank label name gives an empty string');
    }

    @isTest
    static void getLabel_everyKnownName_returnsTheLabelText() {
        for (String name : KNOWN_LABELS) {
            String value = RES_ProductUpdateConfigHelper.getLabel(name);
            Assert.isNotNull(value, name + ' must resolve');
            Assert.areNotEqual('', value, name + ' must have text');
        }
        Assert.areEqual(System.Label.RES_Product_Update_Success,
            RES_ProductUpdateConfigHelper.getLabel('RES_Product_Update_Success'), 'The text is the custom label value');
    }

    @isTest
    static void getLabel_unknownName_returnsTheNameBack() {
        Assert.areEqual('Not_A_Label', RES_ProductUpdateConfigHelper.getLabel('Not_A_Label'),
            'An unknown label name is returned as is');
    }

    @isTest
    static void getAllLabels_returnsAllTenLabels() {
        Map<String, String> labels = RES_ProductUpdateConfigHelper.getAllLabels();

        Assert.areEqual(KNOWN_LABELS.size(), labels.size(), 'Every known label is returned');
        for (String name : KNOWN_LABELS) {
            Assert.isTrue(labels.containsKey(name), name + ' must be in the map');
        }
    }
}
