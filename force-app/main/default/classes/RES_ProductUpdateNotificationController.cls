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
