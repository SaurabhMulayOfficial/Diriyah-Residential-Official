/**
 * @description Controller for global bulk folder document upload and dynamic ProductCode matching using ContentDocument chunking.
 */
public with sharing class RES_BulkFolderUploaderController {

    /**
     * @description Saves base64 chunks sequentially by adding new ContentVersions under the same ContentDocumentId.
     * @param fileName File name with extension.
     * @param base64Data Base64 data chunk.
     * @param documentId ContentDocumentId generated from the first chunk.
     * @return ContentDocumentId string for subsequent chunk iterations.
     */
    @AuraEnabled
    public static String saveFileChunk(String fileName, String base64Data, String documentId) {
        Blob chunkBlob = EncodingUtil.base64Decode(base64Data);
        String cleanFileName = fileName.substringBeforeLast('.');

        ContentVersion cv = new ContentVersion();
        cv.Title = cleanFileName;
        cv.PathOnClient = fileName;
        cv.VersionData = chunkBlob;
        cv.IsMajorVersion = true;

        if (String.isNotBlank(documentId)) {
            // Append chunk as new major version under the established ContentDocumentId
            cv.ContentDocumentId = (Id) documentId;
        }

        if (Schema.sObjectType.ContentVersion.isCreateable()) {
            insert as user cv;
        }

        // Retrieve ContentDocumentId for first chunk
        if (String.isBlank(documentId)) {
            ContentVersion insertedCv = [
                SELECT Id, ContentDocumentId 
                FROM ContentVersion 
                WHERE Id = :cv.Id 
                LIMIT 1
            ];
            documentId = insertedCv.ContentDocumentId;

            // Link ContentDocument to matched Product record on first chunk creation
            linkContentToMatchedProduct(documentId, cleanFileName);
        }

        return documentId;
    }

    /**
     * @description Prefix match helper: Matches Product Code via DAO and creates ContentDocumentLink.
     */
    private static void linkContentToMatchedProduct(Id contentDocumentId, String cleanFileName) {
        List<Product2> allProducts = new RES_Product2DAOLayer().getAllProductsWithCode();

        if (allProducts.isEmpty()) {
            throw new AuraHandledException('No Products with ProductCode found in the org.');
        }

        Map<String, Id> codeToProductIdMap = new Map<String, Id>();
        for (Product2 p : allProducts) {
            codeToProductIdMap.put(p.ProductCode.toUpperCase(), p.Id);
        }

        String matchedProductCode = findMatchingProductCode(cleanFileName, codeToProductIdMap.keySet());

        if (String.isBlank(matchedProductCode)) {
            throw new AuraHandledException('File ' + cleanFileName + ' does not match any existing Product Code.');
        }

        Id productId = codeToProductIdMap.get(matchedProductCode);

        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = contentDocumentId;
        cdl.LinkedEntityId = productId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';

        if (Schema.sObjectType.ContentDocumentLink.isCreateable()) {
            insert as user cdl;
        }
    }

    /**
     * @description Prefix match helper: finds the longest product code matching the start of the filename.
     */
    private static String findMatchingProductCode(String fileName, Set<String> productCodes) {
        String upperFileName = fileName.toUpperCase();
        String bestMatch = null;

        for (String code : productCodes) {
            if (upperFileName.startsWith(code)) {
                if (bestMatch == null || code.length() > bestMatch.length()) {
                    bestMatch = code;
                }
            }
        }
        return bestMatch;
    }
}