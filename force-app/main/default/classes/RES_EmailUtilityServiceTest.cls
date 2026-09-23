/**
 * @description  Test class for RES_EmailUtilityService.
 * @author       Saurabh Mulay
 * @date         23-Sep-2026
 */
@IsTest
private class RES_EmailUtilityServiceTest {

    // ─── Constructor / getEmailInstance ─────────────────────────────────────

    @IsTest
    static void testConstructor_initializesEmailInstance() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        Assert.isNotNull(svc, 'Service instance should not be null');
        Assert.isNotNull(svc.getEmailInstance(), 'Underlying email object should be initialised');
    }

    // ─── hydrateMergeFields ──────────────────────────────────────────────────

    @IsTest
    static void testHydrateMergeFields_basicReplacement() {
        String template = 'Hello {0}, your lead is {1}.';
        List<String> mergeFields = new List<String>{ 'John Doe', 'created successfully' };

        String result = RES_EmailUtilityService.hydrateMergeFields(template, mergeFields);

        Assert.areEqual('Hello John Doe, your lead is created successfully.', result);
    }

    @IsTest
    static void testHydrateMergeFields_nullMergeValue_replacedWithEmpty() {
        String template = 'Name: {0}';
        List<String> mergeFields = new List<String>{ null };

        String result = RES_EmailUtilityService.hydrateMergeFields(template, mergeFields);

        Assert.areEqual('Name: ', result, 'Null merge value should be replaced with empty string');
    }

    @IsTest
    static void testHydrateMergeFields_blankTemplate_returnsBlank() {
        String result = RES_EmailUtilityService.hydrateMergeFields('', new List<String>{ 'value' });
        Assert.areEqual('', result, 'Blank template should be returned as-is');
    }

    @IsTest
    static void testHydrateMergeFields_nullTemplate_returnsNull() {
        String result = RES_EmailUtilityService.hydrateMergeFields(null, new List<String>{ 'value' });
        Assert.isNull(result, 'Null template should return null');
    }

    @IsTest
    static void testHydrateMergeFields_nullMergeFields_returnsTemplate() {
        String template = 'Hello {0}';
        String result = RES_EmailUtilityService.hydrateMergeFields(template, null);
        Assert.areEqual(template, result, 'Null mergeFields should leave template unchanged');
    }

    @IsTest
    static void testHydrateMergeFields_emptyMergeFields_noReplacement() {
        String template = 'Hello {0}';
        String result = RES_EmailUtilityService.hydrateMergeFields(template, new List<String>());
        Assert.areEqual('Hello {0}', result, 'Empty mergeFields list should leave placeholders in place');
    }

    @IsTest
    static void testHydrateMergeFields_multiplePlaceholders() {
        String template = '{0} - {1} - {2}';
        List<String> mergeFields = new List<String>{ 'A', 'B', 'C' };

        String result = RES_EmailUtilityService.hydrateMergeFields(template, mergeFields);

        Assert.areEqual('A - B - C', result);
    }

    // ─── setToAddresses ──────────────────────────────────────────────────────

    @IsTest
    static void testSetToAddresses_setsAddressesOnEmailInstance() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setToAddresses(new List<String>{ 'test@example.com' });

        Assert.areEqual('test@example.com', svc.getEmailInstance().getToAddresses()[0]);
    }

    // ─── setCcAddresses ──────────────────────────────────────────────────────

    @IsTest
    static void testSetCcAddresses_setsAddressesOnEmailInstance() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setCcAddresses(new List<String>{ 'cc@example.com' });

        Assert.areEqual('cc@example.com', svc.getEmailInstance().getCcAddresses()[0]);
    }

    // ─── setBccAddresses ─────────────────────────────────────────────────────

    @IsTest
    static void testSetBccAddresses_setsAddressesOnEmailInstance() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setBccAddresses(new List<String>{ 'bcc@example.com' });

        Assert.areEqual('bcc@example.com', svc.getEmailInstance().getBccAddresses()[0]);
    }

    // ─── setSubject ──────────────────────────────────────────────────────────

    @IsTest
    static void testSetSubject_plain_setsSubject() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setSubject('Test Subject');

        Assert.areEqual('Test Subject', svc.getEmailInstance().getSubject());
    }

    @IsTest
    static void testSetSubject_withMergeFields_hydratesSubject() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setSubject('Hello {0}', new List<String>{ 'World' });

        Assert.areEqual('Hello World', svc.getEmailInstance().getSubject());
    }

    @IsTest
    static void testSetSubject_withNullMergeFields_setsSubjectUnchanged() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setSubject('Hello {0}', null);

        Assert.areEqual('Hello {0}', svc.getEmailInstance().getSubject());
    }

    @IsTest
    static void testSetSubject_withEmptyMergeFields_setsSubjectUnchanged() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setSubject('Hello {0}', new List<String>());

        Assert.areEqual('Hello {0}', svc.getEmailInstance().getSubject());
    }

    // ─── setHtmlBody ─────────────────────────────────────────────────────────

    @IsTest
    static void testSetHtmlBody_plain_setsBody() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setHtmlBody('<p>Hello</p>');

        Assert.areEqual('<p>Hello</p>', svc.getEmailInstance().getHtmlBody());
    }

    @IsTest
    static void testSetHtmlBody_withMergeFields_hydratesBody() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setHtmlBody('<p>{0}</p>', new List<String>{ 'Hydrated' });

        Assert.areEqual('<p>Hydrated</p>', svc.getEmailInstance().getHtmlBody());
    }

    @IsTest
    static void testSetHtmlBody_withNullMergeFields_setsBodyUnchanged() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setHtmlBody('<p>{0}</p>', null);

        Assert.areEqual('<p>{0}</p>', svc.getEmailInstance().getHtmlBody());
    }

    // ─── setPlainTextBody ────────────────────────────────────────────────────

    @IsTest
    static void testSetPlainTextBody_plain_setsBody() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setPlainTextBody('Plain text body');

        Assert.areEqual('Plain text body', svc.getEmailInstance().getPlainTextBody());
    }

    @IsTest
    static void testSetPlainTextBody_withMergeFields_hydratesBody() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setPlainTextBody('Hello {0}', new List<String>{ 'Tester' });

        Assert.areEqual('Hello Tester', svc.getEmailInstance().getPlainTextBody());
    }

    @IsTest
    static void testSetPlainTextBody_withNullMergeFields_setsBodyUnchanged() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setPlainTextBody('Hello {0}', null);

        Assert.areEqual('Hello {0}', svc.getEmailInstance().getPlainTextBody());
    }

    // ─── setSaveAsActivity ───────────────────────────────────────────────────

    @IsTest
    static void testSetSaveAsActivity_false_setsFlag() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setSaveAsActivity(false);

        Assert.isFalse(svc.getEmailInstance().getSaveAsActivity());
    }

    @IsTest
    static void testSetSaveAsActivity_true_setsFlag() {
        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setSaveAsActivity(true);

        Assert.isTrue(svc.getEmailInstance().getSaveAsActivity());
    }

    // ─── setTemplateId / setWhatId / setTargetObjectId ───────────────────────

    @IsTest
    static void testSetWhatId_setsWhatId() {
        Lead l = new Lead(LastName = 'Test', Company = 'TestCo', MobilePhone = '+915021321000');
        insert l;

        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setWhatId(l.Id);

        Assert.areEqual(l.Id, svc.getEmailInstance().getWhatId());
    }

    @IsTest
    static void testSetTargetObjectId_setsTargetObjectId() {
        Lead l = new Lead(LastName = 'Target', Company = 'TestCo', MobilePhone = '+915021321000');
        insert l;

        RES_EmailUtilityService svc = new RES_EmailUtilityService();
        svc.setTargetObjectId(l.Id);

        Assert.areEqual(l.Id, svc.getEmailInstance().getTargetObjectId());
    }
}
