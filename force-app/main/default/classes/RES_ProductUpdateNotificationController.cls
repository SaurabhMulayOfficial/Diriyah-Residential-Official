/**
 * Class Name   : RES_ProductUpdateNotificationController
 * Description  : Controller for sending notifications when products are updated.
 *                Called from ResProductUpdateModal LWC after successful update.
 *
 * Usage:
 *      RES_ProductUpdateNotificationController.notifyProductUpdate(productId);
 */
public without sharing class RES_ProductUpdateNotificationController {

    private static final RES_Product2DAOLayer productDAO = new RES_Product2DAOLayer();

    /**
     * Updates ALL Product2 fields (form fields + status/comments/flag) in system context.
     * Called from ResProductUpdateModal via onsubmit interception so the entire DML
     * bypasses sharing enforcement for Operations users.
     *
     * @param productId          The ID of the product to update
     * @param fieldsJson         JSON-serialized map of form field API names to values
     * @param updateComments     Reason for the amendment
     * @param shouldMoveToDraft  True when unit was Available/Soft Hold/Hard Block
     */
    @AuraEnabled
    public static void updateAllAndNotify(Id productId, String fieldsJson, String updateComments, Boolean shouldMoveToDraft) {
        if (productId == null) {
            throw new AuraHandledException('Product ID is required.');
        }
        try {
            Product2 toUpdate = new Product2(Id = productId);

            if (String.isNotBlank(fieldsJson)) {
                Map<String, Object> rawFields = (Map<String, Object>) JSON.deserializeUntyped(fieldsJson);
                for (String fieldName : rawFields.keySet()) {
                    try {
                        toUpdate.put(fieldName, rawFields.get(fieldName));
                    } catch (Exception fieldEx) {
                        System.debug(LoggingLevel.WARN, 'Skipping field ' + fieldName + ': ' + fieldEx.getMessage());
                    }
                }
            }

            toUpdate.RES_Update_Comments__c = updateComments;
            toUpdate.RES_Update_Requested__c = true;
            if (shouldMoveToDraft == true) {
                toUpdate.RES_Unit_Status__c = 'Draft';
            }

            // Use SYSTEM_MODE to bypass sharing AND object-level CRUD restrictions.
            // Product2 records have a special OWD-based access model; without sharing alone
            // is insufficient — SYSTEM_MODE is required for Operations users to update them.
            Database.SaveResult result = Database.update(toUpdate, true, AccessLevel.SYSTEM_MODE);
            if (!result.isSuccess()) {
                List<String> errors = new List<String>();
                for (Database.Error err : result.getErrors()) {
                    errors.add(err.getMessage());
                }
                throw new AuraHandledException(String.join(errors, ', '));
            }
            notifyProductUpdate(productId);

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in updateAllAndNotify: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Updates Product2 status fields in system context (without sharing) and sends notification.
     * Used by ResProductUpdateModal so Operations users can trigger status transitions
     * even when their sharing access is read-only on the Product2 record.
     *
     * @param productId          The ID of the product to update
     * @param updateComments     Reason for the amendment
     * @param shouldMoveToDraft  True when unit was Available/Soft Hold/Hard Block
     */
    @AuraEnabled
    public static void updateProductAndNotify(Id productId, String updateComments, Boolean shouldMoveToDraft) {
        if (productId == null) {
            throw new AuraHandledException('Product ID is required.');
        }
        try {
            Product2 toUpdate = new Product2(Id = productId);
            toUpdate.RES_Update_Comments__c = updateComments;
            toUpdate.RES_Update_Requested__c = true;
            if (shouldMoveToDraft == true) {
                toUpdate.RES_Unit_Status__c = 'Draft';
            }
            Database.SaveResult result = Database.update(toUpdate, true, AccessLevel.SYSTEM_MODE);
            if (!result.isSuccess()) {
                List<String> errors = new List<String>();
                for (Database.Error err : result.getErrors()) {
                    errors.add(err.getMessage());
                }
                throw new AuraHandledException(String.join(errors, ', '));
            }
            notifyProductUpdate(productId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in updateProductAndNotify: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Sends email notification to Operations team when a product is updated.
     * Called from LWC after successful product update.
     *
     * @param productId The ID of the updated product
     */
    @AuraEnabled
    public static void notifyProductUpdate(Id productId) {
        try {
            if (productId == null) {
                return;
            }

            // Get the updated product
            List<Product2> products = productDAO.getProductsByIds(new Set<Id>{ productId });

            if (products.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'Product not found for notification: ' + productId);
                return;
            }

            Product2 product = products[0];

            // Only send notification if product is in Draft and has update flag
            if (product.RES_Unit_Status__c == 'Draft' && product.RES_Update_Requested__c == true) {
                RES_ProductApprovalNotificationService.notifyProductUpdate(products);
                System.debug(LoggingLevel.INFO, 'Update notification sent for product: ' + productId);
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error sending update notification: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
            // Don't throw exception - notification failure shouldn't block UI
        }
    }
}
