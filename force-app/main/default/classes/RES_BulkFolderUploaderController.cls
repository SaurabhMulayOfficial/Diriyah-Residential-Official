/**
 * @description Controller for global bulk folder document upload and dynamic ProductCode matching.
 */
public with sharing class RES_BulkFolderUploaderController {

    public class FilePayload {
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String base64Data { get; set; }
    }

    /**
     * @description Accepts file payloads, extracts potential product codes, matches Products via DAO layer, and links files.
     * @param filePayloads List of uploaded file base64 payloads.
     * @return Success summary message string.
     */
    @AuraEnabled
    public static String uploadAndAttachFilesToProduct(List<FilePayload> filePayloads) {
        if (filePayloads == null || filePayloads.isEmpty()) {
            throw new AuraHandledException('No files were provided for upload.');
        }

        // 1. Pre-query all ProductCodes using updated DAO layer
        List<Product2> allProducts = new RES_Product2DAOLayer().getAllProductsWithCode();

        if (allProducts.isEmpty()) {
            throw new AuraHandledException('No Products with ProductCode found in the org.');
        }

        // Map ProductCode (uppercase) -> Product2 Id
        Map<String, Id> codeToProductIdMap = new Map<String, Id>();
        for (Product2 p : allProducts) {
            codeToProductIdMap.put(p.ProductCode.toUpperCase(), p.Id);
        }

        // 2. Insert ContentVersion records for files matching product codes
        List<ContentVersion> cvToInsert = new List<ContentVersion>();
        List<Id> targetProductIds = new List<Id>();

        for (FilePayload payload : filePayloads) {
            String cleanFileName = payload.fileName.substringBeforeLast('.');
            String matchedProductCode = findMatchingProductCode(cleanFileName, codeToProductIdMap.keySet());

            if (String.isNotBlank(matchedProductCode)) {
                Id productId = codeToProductIdMap.get(matchedProductCode);

                ContentVersion cv = new ContentVersion();
                cv.Title = cleanFileName;
                cv.PathOnClient = payload.fileName;
                cv.VersionData = EncodingUtil.base64Decode(payload.base64Data);
                cv.IsMajorVersion = true;
                
                cvToInsert.add(cv);
                targetProductIds.add(productId);
            }
        }

        if (cvToInsert.isEmpty()) {
            throw new AuraHandledException('None of the uploaded files matched an existing Product Code.');
        }

        // 3. Bulk Insert ContentVersions
        if (Schema.sObjectType.ContentVersion.isCreateable()) {
            insert as user cvToInsert;
        }

        // 4. Query inserted ContentVersions via DAO Layer
        Set<Id> insertedCvIds = new Map<Id, ContentVersion>(cvToInsert).keySet();
        List<ContentVersion> insertedCvList = new RES_ContentVersionDAOLayer().getContentVersionById(insertedCvIds);

        // Map ContentVersion Id to generated ContentDocumentId
        Map<Id, Id> cvIdToDocIdMap = new Map<Id, Id>();
        for (ContentVersion cv : insertedCvList) {
            cvIdToDocIdMap.put(cv.Id, cv.ContentDocumentId);
        }

        // 5. Build ContentDocumentLinks matching indexed Product IDs
        List<ContentDocumentLink> cdlToInsert = new List<ContentDocumentLink>();
        for (Integer i = 0; i < cvToInsert.size(); i++) {
            ContentVersion cv = cvToInsert[i];
            Id productId = targetProductIds[i];
            Id docId = cvIdToDocIdMap.get(cv.Id);

            if (docId != null && productId != null) {
                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.ContentDocumentId = docId;
                cdl.LinkedEntityId = productId;
                cdl.ShareType = 'V';
                cdl.Visibility = 'AllUsers';
                cdlToInsert.add(cdl);
            }
        }

        if (!cdlToInsert.isEmpty() && Schema.sObjectType.ContentDocumentLink.isCreateable()) {
            insert as user cdlToInsert;
        }

        return cdlToInsert.size() + ' file(s) successfully attached across matched Product records.';
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