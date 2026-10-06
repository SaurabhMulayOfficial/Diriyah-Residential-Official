/**
 * @description Copies the active measurement values of a Product2 onto the Product2 itself (DIR-1797).
 *
 *              Measurement Type -> Product2 field:
 *                Z006 BUA (Build up Area)   -> RES_Build_up_area__c      ("<amount> <UOM>")
 *                Z007 Net Saleable Area     -> RES_Unit_Total_Area__c    ("<amount> <UOM>")
 *                Z009 Plot Area             -> RES_Unit_Plot_Area__c     ("<amount> <UOM>")
 *                Z013 Internal Buildup Area -> RES_Internal_unit_Area__c ("<amount> <UOM>")
 *                Z008 No. of rooms          -> RES_No_of_Bedrooms__c     (whole number)
 *
 *              Active = From <= today <= To (blank From = already started, blank To = no end).
 *              When several records of one type are active, the latest From wins, then the latest CreatedDate.
 *              When none is active the Product2 field is cleared.
 *
 *              Called from: RES_MeasurementServices.syncActiveMeasurementsToProduct (trigger path)
 *                           RES_ProductMeasurementSyncBatch (daily date-boundary path)
 */
public without sharing class RES_ProductMeasurementSyncService {

    private static final String TYPE_BUA = 'Z006';
    private static final String TYPE_NET_SALEABLE = 'Z007';
    private static final String TYPE_PLOT = 'Z009';
    private static final String TYPE_INTERNAL_BUA = 'Z013';
    private static final String TYPE_ROOMS = 'Z008';

    /** Measurement Type code -> Product2 field API name. */
    @TestVisible
    private static final Map<String, String> FIELD_BY_TYPE = new Map<String, String>{
        TYPE_BUA          => 'RES_Build_up_area__c',
        TYPE_NET_SALEABLE => 'RES_Unit_Total_Area__c',
        TYPE_PLOT         => 'RES_Unit_Plot_Area__c',
        TYPE_INTERNAL_BUA => 'RES_Internal_unit_Area__c',
        TYPE_ROOMS        => 'RES_No_of_Bedrooms__c'
    };

    public static Set<String> getTrackedTypes() {
        return FIELD_BY_TYPE.keySet();
    }

    private static String orgTimeZoneId;

    /**
     * @description Today's date in the ORG time zone. Date.today() uses the running user's time zone, which differs per
     *              user (e.g. the user a scheduled flow runs as), so the same instant could be "yesterday" for one run
     *              and "today" for another. The flow schedule start time is org-local, so use the org's calendar day.
     */
    public static Date today() {
        if (orgTimeZoneId == null) {
            orgTimeZoneId = new RES_OrganizationDAO().getTimeZoneSidKey();
        }
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', orgTimeZoneId));
    }

    public static void syncProducts(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return;
        }
        productIds.remove(null);
        if (productIds.isEmpty()) {
            return;
        }

        Date today = today();

        // productId -> type -> winning active measurement
        Map<Id, Map<String, RES_Measurement__c>> winners = new Map<Id, Map<String, RES_Measurement__c>>();
        for (RES_Measurement__c m : new RES_MeasurementDAOLayer().getMeasurementsByProductIdsAndTypes(productIds, FIELD_BY_TYPE.keySet())) {
            if (!isActive(m, today)) {
                continue;
            }
            Map<String, RES_Measurement__c> byType = winners.get(m.RES_Product__c);
            if (byType == null) {
                byType = new Map<String, RES_Measurement__c>();
                winners.put(m.RES_Product__c, byType);
            }
            RES_Measurement__c current = byType.get(m.RES_Measurement_Type__c);
            if (current == null || isBetter(m, current)) {
                byType.put(m.RES_Measurement_Type__c, m);
            }
        }

        List<Product2> toUpdate = new List<Product2>();
        for (Product2 existing : new RES_Product2DAOLayer().getMeasurementFieldsByIds(productIds)) {
            Map<String, RES_Measurement__c> byType = winners.containsKey(existing.Id)
                ? winners.get(existing.Id) : new Map<String, RES_Measurement__c>();
            Product2 upd = new Product2(Id = existing.Id);
            Boolean changed = false;
            for (String typeCode : FIELD_BY_TYPE.keySet()) {
                String fieldName = FIELD_BY_TYPE.get(typeCode);
                Object newValue = buildValue(typeCode, byType.get(typeCode));
                if (existing.get(fieldName) != newValue) {
                    upd.put(fieldName, newValue);
                    changed = true;
                }
            }
            if (changed) {
                toUpdate.add(upd);
            }
        }

        if (toUpdate.isEmpty()) {
            return;
        }
        // Partial success: a product-level failure must not roll back the measurement save
        for (Database.SaveResult sr : Database.update(toUpdate, false)) {
            if (!sr.isSuccess()) {
                System.debug(LoggingLevel.ERROR, '### [RES_ProductMeasurementSyncService] Product2 update failed: ' + sr.getErrors()[0].getMessage());
            }
        }
    }

    @TestVisible
    private static Boolean isActive(RES_Measurement__c m, Date today) {
        return (m.RES_Measurement_From__c == null || m.RES_Measurement_From__c <= today)
            && (m.RES_Measurement_To__c == null || m.RES_Measurement_To__c >= today);
    }

    /** Latest From wins (blank From is oldest), then latest CreatedDate, then higher Id. */
    private static Boolean isBetter(RES_Measurement__c candidate, RES_Measurement__c current) {
        Date candFrom = candidate.RES_Measurement_From__c;
        Date currFrom = current.RES_Measurement_From__c;
        if (candFrom != currFrom) {
            if (candFrom == null) return false;
            if (currFrom == null) return true;
            return candFrom > currFrom;
        }
        if (candidate.CreatedDate != current.CreatedDate) {
            return candidate.CreatedDate > current.CreatedDate;
        }
        return candidate.Id > current.Id; // same-second creates: higher Id was created later
    }

    /** Returns the Product2 field value for the winning measurement, or null (clear) when there is none. */
    @TestVisible
    private static Object buildValue(String typeCode, RES_Measurement__c m) {
        if (m == null || m.RES_Measurement_Amount__c == null) {
            return null;
        }
        if (typeCode == TYPE_ROOMS) {
            return m.RES_Measurement_Amount__c.setScale(0, System.RoundingMode.DOWN);
        }
        String text = m.RES_Measurement_Amount__c.stripTrailingZeros().toPlainString();
        if (String.isNotBlank(m.RES_Unit_Of_Measurement__c)) {
            text += ' ' + m.RES_Unit_Of_Measurement__c;
        }
        return text.left(20); // Product2 target fields are Text(20)
    }
}
