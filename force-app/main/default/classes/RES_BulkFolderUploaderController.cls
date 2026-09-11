/**
 * @class name         : RES_BulkFolderUploaderController
 * @description        : Controller for processing Salesforce Files uploaded through the native file uploader and dynamically linking them to Product2 records using Product Code matching.
 * @created date       : 01/09/2026
 * @last modified Date : 10/09/2026
 * @author             : Nitin Marathe
 */
public with sharing class RES_BulkFolderUploaderController {

    @AuraEnabled
    public static ProcessingResult processUploadedFiles(String uploadedFilesJson) {
        if (String.isBlank(uploadedFilesJson)) {
            throw new AuraHandledException('No uploaded files were received.');
        }

        List<UploadedFile> uploadedFiles = (List<UploadedFile>) JSON.deserialize(uploadedFilesJson, List<UploadedFile>.class);
        if (uploadedFiles == null || uploadedFiles.isEmpty()) {
            throw new AuraHandledException('No uploaded files were received.');
        }

        List<Product2> products = new RES_Product2DAOLayer().getAllProductsWithCode();
        if (products.isEmpty()) {
            throw new AuraHandledException('No Products with ProductCode found in the org.');
        }

        Map<String, Id> codeToProductId = new Map<String, Id>();
        for (Product2 product : products) {
            if (String.isNotBlank(product.ProductCode)) {
                codeToProductId.put(product.ProductCode.trim().toUpperCase(), product.Id);
            }
        }

        List<ContentDocumentLink> linksToCreate = new List<ContentDocumentLink>();
        ProcessingResult result = new ProcessingResult();

        for (UploadedFile uploadedFile : uploadedFiles) {
            try {
                if (String.isBlank(uploadedFile.documentId) || String.isBlank(uploadedFile.name)) {
                    result.failedCount++;
                    continue;
                }

                String cleanFileName = removeExtension(uploadedFile.name);
                String matchedProductCode = findMatchingProductCode(cleanFileName, codeToProductId.keySet());

                if (String.isBlank(matchedProductCode)) {
                    result.failedCount++;
                    continue;
                }

                Id productId = codeToProductId.get(matchedProductCode);

                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.ContentDocumentId = (Id) uploadedFile.documentId;
                cdl.LinkedEntityId = productId;
                cdl.ShareType = 'V';
                cdl.Visibility = 'AllUsers';

                linksToCreate.add(cdl);
            } catch (Exception ex) {
                result.failedCount++;
            }
        }

        if (!linksToCreate.isEmpty() && Schema.sObjectType.ContentDocumentLink.isCreateable()) {
            Database.SaveResult[] saveResults = Database.insert(linksToCreate, false, AccessLevel.USER_MODE);

            for (Database.SaveResult saveResult : saveResults) {
                if (saveResult.isSuccess()) {
                    result.successCount++;
                } else {
                    result.failedCount++;
                }
            }
        } else if (!linksToCreate.isEmpty()) {
            result.failedCount += linksToCreate.size();
        }

        return result;
    }

    private static String removeExtension(String fileName) {
        Integer lastDot = fileName.lastIndexOf('.');
        if (lastDot > 0) {
            return fileName.substring(0, lastDot);
        }
        return fileName;
    }

    private static String findMatchingProductCode(String fileName, Set<String> productCodes) {
        String upperFileName = fileName.toUpperCase();
        String bestMatch;

        for (String code : productCodes) {
            if (String.isBlank(code)) {
                continue;
            }
            if (upperFileName.startsWith(code)) {
                if (bestMatch == null || code.length() > bestMatch.length()) {
                    bestMatch = code;
                }
            }
        }
        return bestMatch;
    }

    public class UploadedFile {
        public String name;
        public String documentId;
    }

    public class ProcessingResult {
        @AuraEnabled public Integer successCount = 0;
        @AuraEnabled public Integer failedCount = 0;
    }
}