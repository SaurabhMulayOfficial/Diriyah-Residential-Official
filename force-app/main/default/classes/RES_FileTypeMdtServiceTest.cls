/**
 * @description  Test class for RES_FileTypeMdtService and RES_FileTypeMdtDAO.
 * @author       Saurabh Mulay
 * @date         23-Sep-2026
 */
@IsTest
private class RES_FileTypeMdtServiceTest {

    // ─── Constructor ─────────────────────────────────────────────────────────

    @IsTest
    static void testServiceConstructor() {
        RES_FileTypeMdtService svc = new RES_FileTypeMdtService();
        Assert.isNotNull(svc, 'Service instance should not be null');
    }

    // ─── RES_FileTypeMdtDAO ──────────────────────────────────────────────────

    @IsTest
    static void testDAO_getFileTypesByObjectName_unknownObject_returnsEmptyList() {
        Test.startTest();
        List<RES_File_Type__mdt> result = new RES_FileTypeMdtDAO().getFileTypesByObjectName('NonExistentObject_xyz_12345');
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null');
        Assert.areEqual(0, result.size(), 'No MDT records expected for a non-existent object name');
    }

    @IsTest
    static void testDAO_getFileTypesByObjectName_nullObjectName_returnsEmptyList() {
        Test.startTest();
        List<RES_File_Type__mdt> result = new RES_FileTypeMdtDAO().getFileTypesByObjectName(null);
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null for null input');
        Assert.areEqual(0, result.size(), 'No MDT records expected for null object name');
    }

    @IsTest
    static void testDAO_getFileTypesByObjectName_emptyString_returnsEmptyList() {
        Test.startTest();
        List<RES_File_Type__mdt> result = new RES_FileTypeMdtDAO().getFileTypesByObjectName('');
        Test.stopTest();

        Assert.isNotNull(result, 'Result should not be null for empty string input');
        Assert.areEqual(0, result.size(), 'No MDT records expected for empty string object name');
    }

    // ─── getFileTypes ────────────────────────────────────────────────────────

    @IsTest
    static void testGetFileTypes_unknownObjectName_returnsEmptyList() {
        Test.startTest();
        List<String> result = RES_FileTypeMdtService.getFileTypes('NonExistentObject_xyz_12345');
        Test.stopTest();

        Assert.isNotNull(result, 'Result list should not be null');
        Assert.areEqual(0, result.size(), 'Empty list expected when no MDT record matches');
    }

    @IsTest
    static void testGetFileTypes_nullObjectName_returnsEmptyList() {
        Test.startTest();
        List<String> result = RES_FileTypeMdtService.getFileTypes(null);
        Test.stopTest();

        Assert.isNotNull(result, 'Result list should not be null for null input');
        Assert.areEqual(0, result.size(), 'Empty list expected for null object name');
    }

    @IsTest
    static void testGetFileTypes_realMdtRecord_returnsSplitTypes() {
        List<RES_File_Type__mdt> allMdt = [
            SELECT Id, RES_Object_Name__c, RES_File_Types__c
            FROM RES_File_Type__mdt
            LIMIT 1
        ];

        if (allMdt.isEmpty()) {
            return; // No MDT seeded in this org — skip assertion
        }

        RES_File_Type__mdt record = allMdt[0];
        String objectName = record.RES_Object_Name__c;
        List<String> expected = record.RES_File_Types__c.split(',');

        Test.startTest();
        List<String> result = RES_FileTypeMdtService.getFileTypes(objectName);
        Test.stopTest();

        Assert.areEqual(expected.size(), result.size(), 'Number of file types should match the MDT record');
    }

    // ─── findObjectNameFromRecordIdPrefix ────────────────────────────────────

    @IsTest
    static void testFindObjectNameFromRecordIdPrefix_validLeadId_returnsLead() {
        Lead l = new Lead(LastName = 'TestLead', Company = 'TestCo', MobilePhone = '+915021321000');
        insert l;

        Test.startTest();
        String objectName = RES_FileTypeMdtService.findObjectNameFromRecordIdPrefix(String.valueOf(l.Id));
        Test.stopTest();

        Assert.areEqual('Lead', objectName, 'Should resolve Lead from its record Id prefix');
    }

    @IsTest
    static void testFindObjectNameFromRecordIdPrefix_knownPrefix_returnsObjectName() {
        Lead l = new Lead(LastName = 'PrefixTest', Company = 'TestCo', MobilePhone = '+915021321000');
        insert l;
        String prefix = String.valueOf(l.Id).substring(0, 3);

        Test.startTest();
        String objectName = RES_FileTypeMdtService.findObjectNameFromRecordIdPrefix(prefix);
        Test.stopTest();

        Assert.areEqual('Lead', objectName, 'Should resolve Lead from its 3-char key prefix');
    }

    @IsTest
    static void testFindObjectNameFromRecordIdPrefix_invalidPrefix_returnsEmpty() {
        Test.startTest();
        String objectName = RES_FileTypeMdtService.findObjectNameFromRecordIdPrefix('ZZZ');
        Test.stopTest();

        Assert.areEqual('', objectName, 'Unknown prefix should return empty string');
    }

    @IsTest
    static void testFindObjectNameFromRecordIdPrefix_tooShortString_returnsEmpty() {
        Test.startTest();
        String objectName = RES_FileTypeMdtService.findObjectNameFromRecordIdPrefix('AB');
        Test.stopTest();

        // substring(0,3) will throw, caught internally — returns empty string
        Assert.areEqual('', objectName, 'Too-short input should return empty string gracefully');
    }

    // ─── publishProcessAttachmentEvent ───────────────────────────────────────

    @IsTest
    static void testPublishProcessAttachmentEvent_validParams_noException() {
        Lead l = new Lead(LastName = 'EventTest', Company = 'TestCo', MobilePhone = '+915021321000');
        insert l;

        Exception caughtEx = null;
        Test.startTest();
        try {
            RES_FileTypeMdtService.publishProcessAttachmentEvent('Lead', String.valueOf(l.Id), 'Upload', 'PDF');
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        Assert.isNull(caughtEx, 'No exception should be thrown for valid event publish');
    }

    @IsTest
    static void testPublishProcessAttachmentEvent_nullParams_noException() {
        Exception caughtEx = null;
        Test.startTest();
        try {
            RES_FileTypeMdtService.publishProcessAttachmentEvent(null, null, null, null);
        } catch (Exception e) {
            caughtEx = e;
        }
        Test.stopTest();

        Assert.isNull(caughtEx, 'No exception should be thrown when null params are passed');
    }
}
