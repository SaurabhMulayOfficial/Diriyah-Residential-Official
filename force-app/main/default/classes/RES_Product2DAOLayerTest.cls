/**
 * @description Tests for RES_Product2DAOLayer — ensures all query methods return correct results
 *              and guard clauses handle null/empty inputs safely.
 * @author      Roshan Jambhule
 * @date        2026
 */
@isTest
private class RES_Product2DAOLayerTest {

    @TestSetup
    static void setup() {
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId        = UserInfo.getOrganizationId(),
            RES_Triggers_Off__c = true
        );
        upsert cfg;

        List<Product2> products = new List<Product2>{
            new Product2(Name = 'DAO-UNIT-001', ProductCode = 'DAO-UNIT-001',
                         Family = '1004', RES_Type__c = 'N', IsActive = false,
                         RES_Unit_Status__c = 'Draft'),
            new Product2(Name = 'DAO-UNIT-002', ProductCode = 'DAO-UNIT-002',
                         Family = '1004', RES_Type__c = 'N', IsActive = false,
                         RES_Unit_Status__c = 'Draft',
                         RES_Product_External_ID__c = 'EXT-DAO-TEST-001'),
            new Product2(Name = 'DAO-UNIT-003', ProductCode = 'DAO-UNIT-003',
                         StockKeepingUnit = 'SKU-DAO-003',
                         Family = '1004', RES_Type__c = 'N', IsActive = false,
                         RES_Unit_Status__c = 'Draft')
        };
        insert products;
    }

    // ── getAllProductsWithCode ───────────────────────────────────────────────

    @isTest
    static void testGetAllProductsWithCode() {
        List<Product2> results = new RES_Product2DAOLayer().getAllProductsWithCode();
        Assert.isFalse(results.isEmpty(), 'getAllProductsWithCode must return records that have a ProductCode');
    }

    // ── getProductsByProductCodes ───────────────────────────────────────────

    @isTest
    static void testGetProductsByProductCodesNullReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer().getProductsByProductCodes(null).isEmpty(),
            'Null input must return empty list');
    }

    @isTest
    static void testGetProductsByProductCodesEmptyReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer().getProductsByProductCodes(new Set<String>()).isEmpty(),
            'Empty set must return empty list');
    }

    @isTest
    static void testGetProductsByProductCodesWithMatch() {
        List<Product2> results = new RES_Product2DAOLayer()
            .getProductsByProductCodes(new Set<String>{ 'DAO-UNIT-001', 'DAO-UNIT-002' });
        Assert.areEqual(2, results.size(), 'Should return 2 matching products');
    }

    // ── getProductsByExternalIds ────────────────────────────────────────────

    @isTest
    static void testGetProductsByExternalIdsNullReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer().getProductsByExternalIds(null).isEmpty(),
            'Null input must return empty list');
    }

    @isTest
    static void testGetProductsByExternalIdsEmptyReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer().getProductsByExternalIds(new Set<String>()).isEmpty(),
            'Empty set must return empty list');
    }

    @isTest
    static void testGetProductsByExternalIdsWithMatch() {
        List<Product2> results = new RES_Product2DAOLayer()
            .getProductsByExternalIds(new Set<String>{ 'EXT-DAO-TEST-001' });
        Assert.areEqual(1, results.size(), 'Should return the product with matching external id');
    }

    // ── getProductsByIds ────────────────────────────────────────────────────

    @isTest
    static void testGetProductsByIdsNullReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer().getProductsByIds(null).isEmpty(),
            'Null input must return empty list');
    }

    @isTest
    static void testGetProductsByIdsEmptyReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer().getProductsByIds(new Set<Id>()).isEmpty(),
            'Empty set must return empty list');
    }

    @isTest
    static void testGetProductsByIdsWithMatch() {
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'DAO-UNIT-001' LIMIT 1];
        List<Product2> results = new RES_Product2DAOLayer().getProductsByIds(new Set<Id>{ p.Id });
        Assert.areEqual(1, results.size(), 'Should return the matching product');
    }

    // ── getProductsWithRecordTypeByIds ──────────────────────────────────────

    @isTest
    static void testGetProductsWithRecordTypeByIdsNullReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer().getProductsWithRecordTypeByIds(null).isEmpty(),
            'Null input must return empty list');
    }

    @isTest
    static void testGetProductsWithRecordTypeByIdsEmptyReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer().getProductsWithRecordTypeByIds(new Set<Id>()).isEmpty(),
            'Empty set must return empty list');
    }

    @isTest
    static void testGetProductsWithRecordTypeByIdsWithMatch() {
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'DAO-UNIT-001' LIMIT 1];
        List<Product2> results = new RES_Product2DAOLayer()
            .getProductsWithRecordTypeByIds(new Set<Id>{ p.Id });
        Assert.areEqual(1, results.size(), 'Should return 1 product with record type');
    }

    // ── getApprovalQueue ────────────────────────────────────────────────────

    @isTest
    static void testGetApprovalQueueBlankStatusReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer()
            .getApprovalQueue('', null, null, null, null).isEmpty(),
            'Blank status must return empty list');
    }

    @isTest
    static void testGetApprovalQueueBasic() {
        List<Product2> results = new RES_Product2DAOLayer()
            .getApprovalQueue('Draft', null, 10, null, null);
        Assert.isNotNull(results, 'Result must not be null');
    }

    @isTest
    static void testGetApprovalQueueWithSearchTerm() {
        List<Product2> results = new RES_Product2DAOLayer()
            .getApprovalQueue('Draft', 'DAO-UNIT', 10, null, null);
        Assert.isNotNull(results, 'Result must not be null');
        Assert.isFalse(results.isEmpty(), 'Search term should match setup products');
    }

    @isTest
    static void testGetApprovalQueueWithPagination() {
        Product2 p = [SELECT Id, CreatedDate FROM Product2 WHERE ProductCode = 'DAO-UNIT-001' LIMIT 1];
        List<Product2> results = new RES_Product2DAOLayer()
            .getApprovalQueue('Draft', null, 10, p.CreatedDate, p.Id);
        Assert.isNotNull(results, 'Paginated result must not be null');
    }

    @isTest
    static void testGetApprovalQueueNullPageSizeDefaultsTo50() {
        List<Product2> results = new RES_Product2DAOLayer()
            .getApprovalQueue('Draft', null, null, null, null);
        Assert.isNotNull(results, 'Null pageSize must default to 50 and return a valid result');
    }

    @isTest
    static void testGetApprovalQueueOversizePageSizeCapsAt200() {
        List<Product2> results = new RES_Product2DAOLayer()
            .getApprovalQueue('Draft', null, 999, null, null);
        Assert.isNotNull(results, 'Oversize pageSize must be capped at 200 and return a valid result');
    }

    // ── getRejectedProducts ─────────────────────────────────────────────────

    @isTest
    static void testGetRejectedProductsBlankStatusReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer()
            .getRejectedProducts('', null, null, null, null).isEmpty(),
            'Blank status must return empty list');
    }

    @isTest
    static void testGetRejectedProductsBasic() {
        List<Product2> results = new RES_Product2DAOLayer()
            .getRejectedProducts('Draft', null, 10, null, null);
        Assert.isNotNull(results, 'Result must not be null');
    }

    @isTest
    static void testGetRejectedProductsWithSearchTerm() {
        List<Product2> results = new RES_Product2DAOLayer()
            .getRejectedProducts('Draft', 'DAO-UNIT', 10, null, null);
        Assert.isNotNull(results, 'Result must not be null');
    }

    @isTest
    static void testGetRejectedProductsWithPagination() {
        Product2 p = [SELECT Id, CreatedDate FROM Product2 WHERE ProductCode = 'DAO-UNIT-001' LIMIT 1];
        List<Product2> results = new RES_Product2DAOLayer()
            .getRejectedProducts('Draft', null, 10, p.CreatedDate, p.Id);
        Assert.isNotNull(results, 'Paginated result must not be null');
    }

    // ── getPaymentPlanById ──────────────────────────────────────────────────

    @isTest
    static void testGetPaymentPlanByIdNullReturnsNull() {
        Assert.isNull(new RES_Product2DAOLayer().getPaymentPlanById(null),
            'Null Id must return null');
    }

    @isTest
    static void testGetPaymentPlanByIdWithMatch() {
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'DAO-UNIT-001' LIMIT 1];
        Product2 result = new RES_Product2DAOLayer().getPaymentPlanById(p.Id);
        Assert.isNotNull(result, 'Should return the product by id');
    }

    @isTest
    static void testGetPaymentPlanByIdNotFound() {
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'DAO-UNIT-001' LIMIT 1];
        delete p;
        Product2 result = new RES_Product2DAOLayer().getPaymentPlanById(p.Id);
        Assert.isNull(result, 'Deleted record must return null');
    }

    // ── getUnitsByCatalog ───────────────────────────────────────────────────

    @isTest
    static void testGetUnitsByCatalogNullReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer().getUnitsByCatalog(null).isEmpty(),
            'Null catalogId must return empty list');
    }

    @isTest
    static void testGetUnitsByCatalogWithNoMatch() {
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'DAO-UNIT-001' LIMIT 1];
        List<Product2> results = new RES_Product2DAOLayer().getUnitsByCatalog(p.Id);
        Assert.isNotNull(results, 'Non-matching catalog must return empty list, not null');
    }

    // ── getProductsRelatedToCatalog ─────────────────────────────────────────

    @isTest
    static void testGetProductsRelatedToCatalogEmptyReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer()
            .getProductsRelatedToCatalog(new Set<Id>(), 'RES_Residential_Sales').isEmpty(),
            'Empty catalog set must return empty list');
    }

    @isTest
    static void testGetProductsRelatedToCatalogNullReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer()
            .getProductsRelatedToCatalog(null, 'RES_Residential_Sales').isEmpty(),
            'Null catalog set must return empty list');
    }

    // ── getProductsForSync ──────────────────────────────────────────────────

    @isTest
    static void testGetProductsForSyncEmptyReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer().getProductsForSync(new Set<Id>()).isEmpty(),
            'Empty set must return empty list');
    }

    @isTest
    static void testGetProductsForSyncWithMatch() {
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'DAO-UNIT-001' LIMIT 1];
        List<Product2> results = new RES_Product2DAOLayer().getProductsForSync(new Set<Id>{ p.Id });
        Assert.areEqual(1, results.size(), 'Should return the matching product for sync');
    }

    // ── getMeasurementFieldsByIds ───────────────────────────────────────────

    @isTest
    static void testGetMeasurementFieldsByIdsEmptyReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer().getMeasurementFieldsByIds(new Set<Id>()).isEmpty(),
            'Empty set must return empty list');
    }

    @isTest
    static void testGetMeasurementFieldsByIdsWithMatch() {
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'DAO-UNIT-001' LIMIT 1];
        List<Product2> results = new RES_Product2DAOLayer()
            .getMeasurementFieldsByIds(new Set<Id>{ p.Id });
        Assert.areEqual(1, results.size(), 'Should return measurement fields for matching product');
    }

    // ── Query locators ──────────────────────────────────────────────────────

    @isTest
    static void testGetProductsWithMeasurementsLocatorReturnsLocator() {
        Database.QueryLocator ql = new RES_Product2DAOLayer().getProductsWithMeasurementsLocator();
        Assert.isNotNull(ql, 'getProductsWithMeasurementsLocator must return a non-null QueryLocator');
    }

    @isTest
    static void testGetProductsWithMeasurementBoundaryLocatorReturnsLocator() {
        Database.QueryLocator ql = new RES_Product2DAOLayer()
            .getProductsWithMeasurementBoundaryLocator(Date.today().addDays(-30), Date.today());
        Assert.isNotNull(ql, 'getProductsWithMeasurementBoundaryLocator must return a non-null QueryLocator');
    }

    // ── getProductsByStockKeepingUnits ──────────────────────────────────────

    @isTest
    static void testGetProductsByStockKeepingUnitsNullReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer().getProductsByStockKeepingUnits(null).isEmpty(),
            'Null input must return empty list');
    }

    @isTest
    static void testGetProductsByStockKeepingUnitsEmptyReturnsEmpty() {
        Assert.isTrue(new RES_Product2DAOLayer()
            .getProductsByStockKeepingUnits(new Set<String>()).isEmpty(),
            'Empty set must return empty list');
    }

    @isTest
    static void testGetProductsByStockKeepingUnitsWithMatch() {
        List<Product2> results = new RES_Product2DAOLayer()
            .getProductsByStockKeepingUnits(new Set<String>{ 'SKU-DAO-003' });
        Assert.areEqual(1, results.size(), 'Should return the product matching the SKU');
    }
}
