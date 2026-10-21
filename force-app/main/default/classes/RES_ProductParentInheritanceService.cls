/**
 * @description Before-save inheritance of validity dates and profit center from a unit's parent
 *              Business Entity / Project / Zone (ProductCatalog) onto the Product2 (unit).
 *              Only blank unit fields are filled, so values entered by users, loaders or approvals are never overwritten.
 *              Must run before the generic date defaults so the parent's dates win over today / 2099-12-31.
 * @author      Roshan Jambhule
 * @date        2025
 */
public with sharing class RES_ProductParentInheritanceService {

    @TestVisible
    private static RES_ProductCatalogDAOLayer catalogDao = new RES_ProductCatalogDAOLayer();

    /**
     * @description Fills AvailabilityDate, DiscontinuedDate and RES_Profit_Center__c from the parent when blank.
     * @param products  Trigger.new of a before insert / before update context
     * @param oldMap    Trigger.oldMap, null on insert. Not required; kept for symmetry with other services.
     */
    public static void applyParentValues(List<Product2> products, Map<Id, Product2> oldMap) {
        if (products == null || products.isEmpty()) return;

        Set<Id> catalogIds = new Set<Id>();
        for (Product2 p : products) {
            if (p.RES_Business_Entity__c != null && needsInheritance(p)) {
                catalogIds.add(p.RES_Business_Entity__c);
            }
        }
        if (catalogIds.isEmpty()) return;

        Map<Id, ProductCatalog> catalogs = new Map<Id, ProductCatalog>();
        try {
            catalogs.putAll(catalogDao.getInheritanceDataByIds(catalogIds));
        } catch (Exception e) {
            // Never block a unit save because the parent could not be read; generic defaults still apply.
            System.debug(LoggingLevel.ERROR, '### [RES_ProductParentInheritanceService] Parent lookup failed: ' + e.getMessage());
            return;
        }

        for (Product2 p : products) {
            if (p.RES_Business_Entity__c == null) continue;
            ProductCatalog parent = catalogs.get(p.RES_Business_Entity__c);
            if (parent == null) continue;

            if (p.AvailabilityDate == null && parent.EffectiveStartDate != null) {
                p.AvailabilityDate = parent.EffectiveStartDate.date();
            }
            if (p.DiscontinuedDate == null && parent.EffectiveEndDate != null) {
                p.DiscontinuedDate = parent.EffectiveEndDate.date();
            }
            if (String.isBlank(p.RES_Profit_Center__c) && String.isNotBlank(parent.RES_Profit_Center__c)) {
                p.RES_Profit_Center__c = parent.RES_Profit_Center__c;
            }
        }
    }

    private static Boolean needsInheritance(Product2 p) {
        return p.AvailabilityDate == null
            || p.DiscontinuedDate == null
            || String.isBlank(p.RES_Profit_Center__c);
    }
}
