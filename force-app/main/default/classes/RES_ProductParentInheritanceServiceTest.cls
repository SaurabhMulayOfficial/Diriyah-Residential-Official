/**
 * @description Tests for RES_ProductParentInheritanceService.
 * @author      Roshan Jambhule
 * @date        2025
 */
@isTest
private class RES_ProductParentInheritanceServiceTest {

    private static final DateTime PARENT_START = DateTime.newInstance(2026, 1, 15, 12, 0, 0);
    private static final DateTime PARENT_END   = DateTime.newInstance(2030, 6, 30, 12, 0, 0);

    private static ProductCatalog makeCatalog(DateTime startDt, DateTime endDt, String profitCenter) {
        ProductCatalog c = new ProductCatalog(
            Name = 'Parent Catalog',
            CatalogType = 'Sales',
            EffectiveStartDate = startDt,
            EffectiveEndDate = endDt,
            RES_Profit_Center__c = profitCenter
        );
        insert c;
        return c;
    }

    @isTest
    static void testBlankFieldsInheritFromParent() {
        ProductCatalog c = makeCatalog(PARENT_START, PARENT_END, 'PC1000');
        Product2 p = new Product2(Name = 'Unit A', RES_Business_Entity__c = c.Id);

        RES_ProductParentInheritanceService.applyParentValues(new List<Product2>{ p }, null);

        System.assertEquals(PARENT_START.date(), p.AvailabilityDate, 'Availability date should come from parent start');
        System.assertEquals(PARENT_END.date(), p.DiscontinuedDate, 'Discontinued date should come from parent end');
        System.assertEquals('PC1000', p.RES_Profit_Center__c, 'Profit center should come from parent');
    }

    @isTest
    static void testExistingValuesAreNotOverwritten() {
        ProductCatalog c = makeCatalog(PARENT_START, PARENT_END, 'PC1000');
        Product2 p = new Product2(
            Name = 'Unit B',
            RES_Business_Entity__c = c.Id,
            AvailabilityDate = Date.newInstance(2026, 3, 1),
            DiscontinuedDate = Date.newInstance(2028, 3, 1),
            RES_Profit_Center__c = 'UNIT_PC'
        );

        RES_ProductParentInheritanceService.applyParentValues(new List<Product2>{ p }, null);

        System.assertEquals(Date.newInstance(2026, 3, 1), p.AvailabilityDate);
        System.assertEquals(Date.newInstance(2028, 3, 1), p.DiscontinuedDate);
        System.assertEquals('UNIT_PC', p.RES_Profit_Center__c);
    }

    @isTest
    static void testParentWithNullValuesLeavesUnitBlank() {
        ProductCatalog c = makeCatalog(null, null, null);
        Product2 p = new Product2(Name = 'Unit C', RES_Business_Entity__c = c.Id);

        RES_ProductParentInheritanceService.applyParentValues(new List<Product2>{ p }, null);

        System.assertEquals(null, p.AvailabilityDate);
        System.assertEquals(null, p.DiscontinuedDate);
        System.assertEquals(null, p.RES_Profit_Center__c);
    }

    @isTest
    static void testNoParentAndNullInputsAreSafe() {
        Product2 p = new Product2(Name = 'Unit D');

        RES_ProductParentInheritanceService.applyParentValues(new List<Product2>{ p }, null);
        RES_ProductParentInheritanceService.applyParentValues(null, null);
        RES_ProductParentInheritanceService.applyParentValues(new List<Product2>(), null);

        System.assertEquals(null, p.AvailabilityDate);
        System.assertEquals(null, p.RES_Profit_Center__c);
    }

    @isTest
    static void testPartialFillOnlyBlankFields() {
        ProductCatalog c = makeCatalog(PARENT_START, PARENT_END, 'PC1000');
        Product2 p = new Product2(
            Name = 'Unit E',
            RES_Business_Entity__c = c.Id,
            AvailabilityDate = Date.newInstance(2026, 3, 1)
        );

        RES_ProductParentInheritanceService.applyParentValues(new List<Product2>{ p }, null);

        System.assertEquals(Date.newInstance(2026, 3, 1), p.AvailabilityDate, 'Existing start date kept');
        System.assertEquals(PARENT_END.date(), p.DiscontinuedDate, 'Blank end date inherited');
        System.assertEquals('PC1000', p.RES_Profit_Center__c, 'Blank profit center inherited');
    }

    @isTest
    static void testBulkUnitsShareOneParentQuery() {
        // One catalog only: the catalog sync starts a batch per inserted record and tests allow a single executeBatch.
        ProductCatalog c = makeCatalog(PARENT_START, PARENT_END, 'PC1');
        List<Product2> units = new List<Product2>();
        for (Integer i = 0; i < 50; i++) {
            units.add(new Product2(Name = 'Bulk ' + i, RES_Business_Entity__c = c.Id));
        }

        Integer before = Limits.getQueries();
        RES_ProductParentInheritanceService.applyParentValues(units, null);
        Integer used = Limits.getQueries() - before;

        System.assertEquals(1, used, 'One query regardless of unit count');
        for (Product2 p : units) {
            System.assertEquals('PC1', p.RES_Profit_Center__c);
            System.assertEquals(PARENT_START.date(), p.AvailabilityDate);
        }
    }

    @isTest
    static void testDaoReturnsInheritanceFieldsAndHandlesEmptyInput() {
        ProductCatalog c = makeCatalog(PARENT_START, PARENT_END, 'PC9');
        RES_ProductCatalogDAOLayer dao = new RES_ProductCatalogDAOLayer();

        System.assert(dao.getInheritanceDataByIds(null).isEmpty());
        System.assert(dao.getInheritanceDataByIds(new Set<Id>()).isEmpty());
        System.assert(dao.getCatalogByIds(new Set<Id>()).isEmpty());

        List<ProductCatalog> lean = dao.getInheritanceDataByIds(new Set<Id>{ c.Id });
        System.assertEquals(1, lean.size());
        System.assertEquals('PC9', lean[0].RES_Profit_Center__c);

        List<ProductCatalog> full = dao.getCatalogByIds(new Set<Id>{ c.Id });
        System.assertEquals(1, full.size());
        System.assertEquals(1, dao.getCatalogsByCodes(new Set<String>{ 'NO_SUCH_CODE' }).size() + 1);
        System.assert(dao.getCatalogsByCodes(null).isEmpty());
    }
}
