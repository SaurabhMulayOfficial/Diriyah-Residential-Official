@IsTest
private class RES_ImageDimensionUtilTest {

    // PNG 100x200
    private static final String PNG_HEX = '89504e470d0a1a0a0000000d4948445200000064000000c80806000000';
    // GIF 10x20
    private static final String GIF_HEX = '4749463839610a001400f70000000000';
    // JPEG 600x400 with APP0 segment and a fill byte before SOF0
    private static final String JPEG_HEX = 'ffd8ffe000104a46494600010100000100010000'
        + 'ffffc000110801900258030122000211010311010000000000';

    private static Blob hex(String h) {
        return EncodingUtil.convertFromHex(h);
    }

    private static ContentVersion insertFile(String title, Blob data) {
        ContentVersion cv = new ContentVersion(Title = title, PathOnClient = title, VersionData = data);
        insert cv;
        return [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
    }

    @IsTest
    static void pngFromContentVersionId() {
        ContentVersion cv = insertFile('img.png', hex(PNG_HEX));
        Test.startTest();
        Map<String, Integer> d = RES_ImageDimensionUtil.getDimensions(cv.Id);
        Test.stopTest();
        Assert.areEqual(100, d.get('width'));
        Assert.areEqual(200, d.get('height'));
    }

    @IsTest
    static void jpegFromContentDocumentId() {
        ContentVersion cv = insertFile('img.jpg', hex(JPEG_HEX));
        Test.startTest();
        Map<String, Integer> d = RES_ImageDimensionUtil.getDimensions(cv.ContentDocumentId);
        Test.stopTest();
        Assert.areEqual(600, d.get('width'));
        Assert.areEqual(400, d.get('height'));
    }

    @IsTest
    static void gifFromBlob() {
        Map<String, Integer> d = RES_ImageDimensionUtil.getDimensions(hex(GIF_HEX));
        Assert.areEqual(10, d.get('width'));
        Assert.areEqual(20, d.get('height'));
    }

    @IsTest
    static void jpegWithoutSofReturnsNull() {
        // RST marker then SOS before any SOF
        Blob b = hex('ffd8ffd0ffda000c03010002110311003f00000000000000');
        Assert.isNull(RES_ImageDimensionUtil.getDimensions(b));
    }

    @IsTest
    static void unsupportedOrMissingReturnsNull() {
        Assert.isNull(RES_ImageDimensionUtil.getDimensions(Blob.valueOf('not an image at all, plain text')));
        Assert.isNull(RES_ImageDimensionUtil.getDimensions((Blob) null));
        ContentVersion cv = insertFile('a.txt', Blob.valueOf('x'));
        delete [SELECT Id FROM ContentDocument WHERE Id = :cv.ContentDocumentId];
        Assert.isNull(RES_ImageDimensionUtil.getDimensions(cv.Id));
    }
}
