/**
 * @description Tests for RES_ProductService.shareDocumentImages — sharing of the SPA document image file with the Chatter groups.
 */
@isTest
private class RES_ProductDocumentImageShareTest {

    private static final String IMAGE_NAME = 'D6-2-B-009';

    // Chatter groups are not visible to tests and their names are unique org-wide, so use test-only names.
    private static final String SPECIALISTS = 'Test Specialists - Document Images';
    private static final String ADMINS = 'Test Admins - Document Images';

    private static Map<String, Id> ensureGroups() {
        // Custom metadata cannot be inserted in tests, so inject the group config (name => share type).
        RES_ProductService.shareGroupOverride = new Map<String, String>{ SPECIALISTS => 'V', ADMINS => 'C' };
        List<CollaborationGroup> groups = new List<CollaborationGroup>{
            new CollaborationGroup(Name = SPECIALISTS, CollaborationType = 'Public'),
            new CollaborationGroup(Name = ADMINS, CollaborationType = 'Public')
        };
        insert groups;
        return new Map<String, Id>{ 'Specialists - Document Images' => groups[0].Id, 'Admins - Document Images' => groups[1].Id };
    }

    private static Product2 createProductWithFile(String fileTitle) {
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(SetupOwnerId = UserInfo.getOrganizationId(), RES_Triggers_Off__c = true);
        upsert cfg;
        Product2 p = new Product2(Name = 'Test Unit', RES_SPA_Document_Image_Name__c = IMAGE_NAME);
        insert p;

        ContentVersion cv = new ContentVersion(Title = fileTitle, PathOnClient = fileTitle + '.png', VersionData = Blob.valueOf('img'));
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = p.Id, ShareType = 'V');
        return p;
    }

    private static Set<Id> linkedEntityIds(Id docId) {
        Set<Id> ids = new Set<Id>();
        for (ContentDocumentLink l : [SELECT LinkedEntityId FROM ContentDocumentLink WHERE ContentDocumentId = :docId]) {
            ids.add(l.LinkedEntityId);
        }
        return ids;
    }

    @isTest
    static void sharesMatchingFileWithBothGroups() {
        Map<String, Id> groups = ensureGroups();
        Product2 p = createProductWithFile(IMAGE_NAME);
        Id docId = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :p.Id LIMIT 1].ContentDocumentId;

        Test.startTest();
        RES_ProductService.shareDocumentImages(new List<Product2>{ p }, null);
        Test.stopTest();

        Set<Id> linked = linkedEntityIds(docId);
        System.assert(linked.contains(groups.get('Specialists - Document Images')), 'Specialists Chatter group should have access');
        System.assert(linked.contains(groups.get('Admins - Document Images')), 'Admins Chatter group should have access');
        System.assert(linked.contains(UserInfo.getUserId()), 'Uploader keeps access');
    }

    @isTest
    static void usesShareTypeConfiguredPerGroup() {
        Map<String, Id> groups = ensureGroups();
        Product2 p = createProductWithFile(IMAGE_NAME);
        Id docId = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :p.Id LIMIT 1].ContentDocumentId;

        RES_ProductService.shareDocumentImages(new List<Product2>{ p }, null);

        Map<Id, String> shareTypes = new Map<Id, String>();
        for (ContentDocumentLink l : [SELECT LinkedEntityId, ShareType FROM ContentDocumentLink WHERE ContentDocumentId = :docId]) {
            shareTypes.put(l.LinkedEntityId, l.ShareType);
        }
        System.assertEquals('V', shareTypes.get(groups.get('Specialists - Document Images')), 'Specialists get Viewer');
        System.assertEquals('C', shareTypes.get(groups.get('Admins - Document Images')), 'Admins get Collaborator');
    }

    @isTest
    static void doesNothingWhenNoGroupsConfigured() {
        Map<String, Id> groups = ensureGroups();
        RES_ProductService.shareGroupOverride = new Map<String, String>();
        Product2 p = createProductWithFile(IMAGE_NAME);
        Id docId = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :p.Id LIMIT 1].ContentDocumentId;
        Integer before = linkedEntityIds(docId).size();

        RES_ProductService.shareDocumentImages(new List<Product2>{ p }, null);

        Set<Id> linked = linkedEntityIds(docId);
        System.assertEquals(before, linked.size(), 'No new links created');
        System.assertEquals(false, linked.contains(groups.get('Specialists - Document Images')), 'No group should be linked');
        System.assertEquals(false, linked.contains(groups.get('Admins - Document Images')), 'No group should be linked');
    }

    @isTest
    static void readsGroupsFromCustomMetadata() {
        RES_ProductService.shareGroupOverride = null;
        Map<String, String> configured = RES_ProductService.getDocumentImageShareGroups();
        for (RES_Document_Image_Share_Group__mdt cfg : RES_Document_Image_Share_Group__mdt.getAll().values()) {
            if (String.isBlank(cfg.RES_Group_Name__c)) {
                continue;
            }
            System.assertEquals(cfg.RES_Is_Active__c, configured.containsKey(cfg.RES_Group_Name__c.trim()), 'Only active records are used');
        }
    }

    @isTest
    static void doesNotShareWhenNameUnchangedOrNoMatch() {
        Map<String, Id> groups = ensureGroups();
        Product2 p = createProductWithFile('Some Other File');
        Id docId = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :p.Id LIMIT 1].ContentDocumentId;

        RES_ProductService.shareDocumentImages(new List<Product2>{ p }, null);
        Product2 same = p.clone(true);
        RES_ProductService.shareDocumentImages(new List<Product2>{ same }, new Map<Id, Product2>{ p.Id => p });

        System.assertEquals(false, linkedEntityIds(docId).contains(groups.get('Specialists - Document Images')), 'No match, no share');
    }

    @isTest
    static void rerunDoesNotCreateDuplicates() {
        ensureGroups();
        Product2 p = createProductWithFile(IMAGE_NAME);
        Id docId = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :p.Id LIMIT 1].ContentDocumentId;

        RES_ProductService.shareDocumentImages(new List<Product2>{ p }, null);
        Integer first = linkedEntityIds(docId).size();
        RES_ProductService.shareDocumentImages(new List<Product2>{ p }, null);

        System.assertEquals(first, linkedEntityIds(docId).size(), 'No duplicate links');
    }

    @isTest
    static void contentDocumentLinkDaoQueriesReturnLinks() {
        ensureGroups();
        Product2 p = createProductWithFile(IMAGE_NAME);
        Id docId = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :p.Id LIMIT 1].ContentDocumentId;
        RES_ContentDocumentLinkDAOLayer dao = new RES_ContentDocumentLinkDAOLayer();

        System.assertEquals(1, dao.getContentDocumentLinkByLinkedId(p.Id).size());
        System.assertEquals(1, dao.getEmailAttachmentLinksByLinkedIds(new Set<Id>{ p.Id }).size());
        System.assertEquals(1, dao.getLinksWithTitleByLinkedEntityIds(new Set<Id>{ p.Id }).size());
        System.assertEquals(1, dao.getLinksByLinkedEntityIds(new Set<Id>{ p.Id }).size());
        System.assert(!dao.getContentDocumentLinkByContentDocumentId(new Set<Id>{ docId }).isEmpty());
        System.assert(!dao.getLinksByContentDocumentIds(new Set<Id>{ docId }).isEmpty());

        System.assert(dao.getEmailAttachmentLinksByLinkedIds(null).isEmpty());
        System.assert(dao.getLinksWithTitleByLinkedEntityIds(null).isEmpty());
        System.assert(dao.getLinksByLinkedEntityIds(null).isEmpty());
        System.assert(dao.getLinksByContentDocumentIds(null).isEmpty());
    }
}