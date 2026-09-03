/**
 * Class Name   : RES_Product2DAOLayer
 * Description  : Data Access Object (DAO) layer for the Product2 object.
 *                Provides standardized methods for querying and retrieving
 *                Product2 records within the application.
 *
 * Framework Rule:
 *      - All DAO layers must extend RES_BaseDAOLayer.
 *      - Each implementation must override getSObjectName()
 *        to specify the associated SObject.
 */

/**
 * =============================================================================
 * QUERY EXECUTION GUIDELINES
 * =============================================================================
 *
 * 1. Standard Query Execution
 *    Method:
 *      executeQuery(String soql,
 *                   String cacheSuffix,
 *                   Boolean useCache,
 *                   Map<String, Object> bindVars,
 *                   AccessLevel accessLevel)
 *    To get Map<id, Sobject> use executeQueryToMap(<Same Params as above>).
 * 
 *    Usage Guidelines:
 *      - Enable caching ONLY for static queries where data does not change frequently.
 *      - For dynamic queries:
 *            • Set useCache = false
 *            • Set cacheSuffix = ''
 *
 * 2. Batch Query Execution
 *    Method:
 *      executeBatchQuery(String soql,
 *                        Map<String, Object> bindVars,
 *                        AccessLevel accessLevel)
 * =============================================================================
 */
public without sharing class RES_Product2DAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'Product2';
    }

    /**
     * Retrieves all Product2 records having a non-null ProductCode.
     * Used for matching uploaded folder file names with Product Codes across the org.
     */
    public List<Product2> getAllProductsWithCode() {
        String soql = 'SELECT Id, ProductCode FROM Product2 WHERE ProductCode != NULL';
        return (List<Product2>) executeQuery(soql, '', false, new Map<String, Object>(), AccessLevel.USER_MODE);
    }

    /**
     * Retrieves Product2 records matching a specific set of ProductCodes.
     */
    public List<Product2> getProductsByProductCodes(Set<String> productCodes) {
        if (productCodes == null || productCodes.isEmpty()) {
            return new List<Product2>();
        }
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('productCodes', productCodes);
        String soql = 'SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN :productCodes';
        return (List<Product2>) executeQuery(soql, '', false, bindVars, AccessLevel.USER_MODE);
    }

    /**
     * NOTE: Name and ProductCode were added below (2026-08-22) because
     * RES_ProductApprovalNotificationService.buildProductDetails() reads
     * these fields from the same Product2 records this method returns, for
     * approve/reject email content. Without them, that call throws
     * "SObject row was retrieved via SOQL without querying the requested
     * field: Product2.Name" as soon as a notification is sent. If further
     * fields are ever added to that email content, add them here too.
     */
    public List<Product2> getProductsByIds(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<Product2>();
        } 
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('productIds', productIds);
        String soql = 'SELECT Id, Name, ProductCode, IsActive, RES_Unit_Status__c, RES_HardBlock_Start__c, RES_Is_In_Soft_Hold_Extension__c, RES_Soft_Hold_Start__c, RES_Soft_Hold_Until__c FROM Product2 WHERE Id IN :productIds';
        return (List<Product2>) executeQuery(soql,'', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Retrieves Product2 records for an approval queue.
     *
     * Uses keyset pagination:
     * CreatedDate + Id
     *
     * This avoids OFFSET-based pagination for large inventories.
     */
    public List<Product2> getApprovalQueue(String status,String searchTerm,Integer pageSize,Datetime lastCreatedDate,Id lastId) {
        if (String.isBlank(status)) {
            return new List<Product2>();
        }
        Integer safePageSize = normalizePageSize(pageSize);
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('status', status);
        String soql =
            'SELECT Id, ' +
            'Name, ' +
            'ProductCode, ' +
            'IsActive, ' +
            'CreatedDate, ' +
            'CreatedById, ' +
            'CreatedBy.Name, ' +
            'LastModifiedDate, ' +
            'RES_Unit_Status__c, ' +
            'RES_Type__c, ' +
            'RES_Area__c, ' +
            'RES_Business_Entity__c, ' +
            'RES_Unit_Handover_Date__c, ' +
            'RES_Unit_Virtual_IBAN__c, ' +
            'RES_Rejection_Comment__c ' +
            'FROM Product2 ' +
            'WHERE RES_Unit_Status__c = :status ' +
            'AND IsActive = false ';

        if (!String.isBlank(searchTerm)) {
            String searchPattern ='%' + searchTerm.trim() + '%';
            bindVars.put('searchPattern',searchPattern);
            soql +=
                'AND (' +
                'Name LIKE :searchPattern ' +
                'OR ProductCode LIKE :searchPattern ' +
                'OR Description LIKE :searchPattern' +
                ') ';
        }

        /*
         * Keyset pagination.
         */
        if (lastCreatedDate != null && lastId != null) {
            bindVars.put('lastCreatedDate',lastCreatedDate);
            bindVars.put('lastId',lastId);
            soql +=
                'AND (' +
                'CreatedDate < :lastCreatedDate ' +
                'OR (' +
                'CreatedDate = :lastCreatedDate ' +
                'AND Id < :lastId' +
                ')' +
                ') ';
        }

        soql +=
            'ORDER BY CreatedDate DESC, Id DESC ' +
            'LIMIT ' + safePageSize;

        return (List<Product2>) executeQuery(
            soql,
            '',
            false,
            bindVars,
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * Retrieves rejected Products for the Operations rejected queue.
     *
     * Returns only inactive Products with Rejected OR Draft status.
     * Supports comma-separated status values (e.g., "Draft,Rejected").
     *
     * Uses keyset pagination:
     * CreatedDate + Id
     */
    public List<Product2> getRejectedProducts(String status,String searchTerm,Integer pageSize,Datetime lastCreatedDate,Id lastId) {
        if (String.isBlank(status)) {
            return new List<Product2>();
        }
        Integer safePageSize = normalizePageSize(pageSize);
        Map<String, Object> bindVars = new Map<String, Object>();

        // Support multiple statuses separated by comma (e.g., "Draft,Rejected")
        List<String> statuses = status.split(',');
        List<String> trimmedStatuses = new List<String>();
        for (String s : statuses) {
            if (!String.isBlank(s)) {
                trimmedStatuses.add(s.trim());
            }
        }
        bindVars.put('statuses', trimmedStatuses);

        String soql =
                    'SELECT ' +
                    'Id, ' +
                    'Name, ' +
                    'ProductCode, ' +
                    'Description, ' +
                    'IsActive, ' +
                    'CreatedDate, ' +
                    'CreatedById, ' +
                    'CreatedBy.Name, ' +
                    'LastModifiedDate, ' +
                    'RES_Unit_Status__c, ' +
                    'RES_Type__c, ' +
                    'RES_Area__c, ' +
                    'RES_Business_Entity__c, ' +
                    'RES_Unit_Handover_Date__c, ' +
                    'RES_Unit_Virtual_IBAN__c, ' +
                    'RES_Rejection_Comment__c, ' +
                    'Family ' +
                    'FROM Product2 ' +
                    'WHERE RES_Unit_Status__c IN :statuses ' +
                    'AND IsActive = false ';
        if (!String.isBlank(searchTerm)) {
            String searchPattern = '%' + searchTerm.trim() + '%';
            bindVars.put('searchPattern',searchPattern);
            soql +=
                    'AND (' +
                    'Name LIKE :searchPattern ' +
                    'OR ProductCode LIKE :searchPattern ' +
                    'OR Description LIKE :searchPattern' +
                    ') ';
        }

        if (lastCreatedDate != null && lastId != null) {
            bindVars.put('lastCreatedDate',lastCreatedDate);
            bindVars.put('lastId',lastId);
            soql +=
                    'AND (' +
                    'CreatedDate < :lastCreatedDate ' +
                    'OR (' +
                    'CreatedDate = :lastCreatedDate ' +
                    'AND Id < :lastId' +
                    ')' +
                    ') ';
        }

        soql +=
            'ORDER BY CreatedDate DESC, Id DESC ' +
            'LIMIT ' + safePageSize;

        return (List<Product2>) executeQuery(soql,'',false,bindVars,AccessLevel.SYSTEM_MODE);
    }

    /**
     * Normalizes requested page size.
     */
    private Integer normalizePageSize(Integer requestedPageSize) {
        if (
            requestedPageSize == null ||
            requestedPageSize <= 0
        ) {
            return 50;
        }
        if (requestedPageSize > 200) {
            return 200;
        }

        return requestedPageSize;
    }
}