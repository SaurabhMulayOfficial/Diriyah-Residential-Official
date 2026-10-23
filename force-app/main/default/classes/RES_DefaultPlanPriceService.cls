/**
 * @description Maintains Product2.RES_Default_Plan_Price__c on Residential Sales units: the unit price under its default
 * Payment Plan's pricing option adjustment, pre-formatted for the Browse Catalogs product list (RES_Custom_Browse_Products).
 * Set on unit activation, and refreshed when Payment Plan components are provisioned or the unit's adjustments change.
 */
public without sharing class RES_DefaultPlanPriceService {

    private static final String RESIDENTIAL_SALES_RECORD_TYPE = 'RES_Residential_Sales';
    private static final Id RESIDENTIAL_SALES_RECORD_TYPE_ID = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName()
        .get(RESIDENTIAL_SALES_RECORD_TYPE)?.getRecordTypeId();
    private static final String DEFAULT_CURRENCY = 'SAR';

    private static final RES_Product2DAOLayer PRODUCT_DAO = new RES_Product2DAOLayer();
    private static final RES_ProductRelatedComponentDAOLayer COMPONENT_DAO = new RES_ProductRelatedComponentDAOLayer();

    /** Before update: stamps the price on Residential Sales units turning Active, without extra DML. */
    public static void applyOnActivation(List<Product2> newProducts, Map<Id, Product2> oldMap) {
        if (oldMap == null || RESIDENTIAL_SALES_RECORD_TYPE_ID == null) {
            return;
        }
        Map<Id, Product2> activatedById = new Map<Id, Product2>();
        for (Product2 product : newProducts) {
            Product2 oldProduct = oldMap.get(product.Id);
            if (product.RecordTypeId == RESIDENTIAL_SALES_RECORD_TYPE_ID && product.IsActive == true && oldProduct?.IsActive != true) {
                activatedById.put(product.Id, product);
            }
        }
        if (activatedById.isEmpty()) {
            return;
        }
        Map<Id, Decimal> priceByUnitId = defaultPlanPrices(activatedById.keySet());
        for (Product2 product : activatedById.values()) {
            product.RES_Default_Plan_Price__c = formatPrice(priceByUnitId.get(product.Id), product.CurrencyIsoCode);
        }
    }

    /** Recalculates and saves the price for the given units (non-units are ignored); failures are logged, never thrown. */
    public static void refresh(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty() || RESIDENTIAL_SALES_RECORD_TYPE_ID == null) {
            return;
        }
        List<Product2> units = PRODUCT_DAO.getUnitsForDefaultPlanPrice(productIds, RESIDENTIAL_SALES_RECORD_TYPE_ID);
        if (units.isEmpty()) {
            return;
        }

        Map<Id, Decimal> priceByUnitId = defaultPlanPrices(new Map<Id, Product2>(units).keySet());
        List<Product2> toUpdate = new List<Product2>();
        for (Product2 unit : units) {
            String price = formatPrice(priceByUnitId.get(unit.Id), unit.CurrencyIsoCode);
            if (price != unit.RES_Default_Plan_Price__c) {
                toUpdate.add(new Product2(Id = unit.Id, RES_Default_Plan_Price__c = price));
            }
        }
        if (toUpdate.isEmpty()) {
            return;
        }
        Database.SaveResult[] results = Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
        for (Integer index = 0; index < results.size(); index++) {
            if (!results[index].isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'RES_DefaultPlanPriceService: update failed for Unit ' + toUpdate[index].Id + ' - ' + results[index].getErrors());
            }
        }
    }

    /** Raw (unformatted) default-plan price per unit for callers that do their own display formatting, e.g. emails. */
    public static Map<Id, Decimal> getDefaultPlanPrices(Set<Id> unitIds) {
        if (unitIds == null || unitIds.isEmpty()) {
            return new Map<Id, Decimal>();
        }
        return defaultPlanPrices(unitIds);
    }

    /** Adjustment value under each unit's default Payment Plan option; units without one are omitted. */
    @TestVisible
    private static Map<Id, Decimal> defaultPlanPrices(Set<Id> unitIds) {
        Map<Id, Id> defaultPlanIdByUnitId = new Map<Id, Id>();
        for (ProductRelatedComponent component : COMPONENT_DAO.getGroupComponentsByUnits(unitIds, RES_PaymentPlanBundleProvisioner.GROUP_NAME)) {
            if (component.IsDefaultComponent && !defaultPlanIdByUnitId.containsKey(component.ParentProductId)) {
                defaultPlanIdByUnitId.put(component.ParentProductId, component.ChildProductId);
            }
        }
        return RES_ResidentialBundlePricingHook.planAdjustmentValues(defaultPlanIdByUnitId);
    }

    /** Locale-independent display text, e.g. 2,500,000 SAR (decimals kept only when present); null clears the field. */
    @TestVisible
    private static String formatPrice(Decimal amount, String currencyIsoCode) {
        if (amount == null) {
            return null;
        }
        Decimal rounded = amount.setScale(2, RoundingMode.HALF_UP);
        Decimal whole = rounded.setScale(0, RoundingMode.DOWN);
        String digits = String.valueOf(whole.abs());
        String grouped = '';
        while (digits.length() > 3) {
            grouped = ',' + digits.right(3) + grouped;
            digits = digits.left(digits.length() - 3);
        }
        grouped = (rounded < 0 ? '-' : '') + digits + grouped;
        Decimal fraction = (rounded - whole).abs();
        if (fraction > 0) {
            grouped += '.' + String.valueOf(fraction).substringAfter('.').rightPad(2, '0');
        }
        return grouped + ' ' + (String.isBlank(currencyIsoCode) ? DEFAULT_CURRENCY : currencyIsoCode);
    }

}
