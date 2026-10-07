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
 *              Every measurement (any type) also gets RES_Active__c: true only on the one record per product and type
 *              that is in effect (the winner below), false on all others.
 *
 *              Active = From <= today <= To (blank From = already started, blank To = no end).
 *              When several records of one type are in window, the latest effective start wins: the start of the From
 *              date, or the creation moment when From is blank. Ties: latest CreatedDate, then higher Id.
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

    private static String getOrgTimeZoneId() {
        if (orgTimeZoneId == null) {
            orgTimeZoneId = new RES_OrganizationDAO().getTimeZoneSidKey();
        }
        return orgTimeZoneId;
    }

    /**
     * @description Today's date in the ORG time zone. Date.today() uses the running user's time zone, which differs per
     *              user (e.g. the user a scheduled flow runs as), so the same instant could be "yesterday" for one run
     *              and "today" for another. The flow schedule start time is org-local, so use the org's calendar day.
     */
    public static Date today() {
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', getOrgTimeZoneId()));
    }

    /**
     * @description The moment a measurement takes effect: the start of its From date (org time zone), or - when From is
     *              blank - the moment the record was created.
     */
    @TestVisible
    private static Datetime effectiveStart(RES_Measurement__c m) {
        if (m.RES_Measurement_From__c == null) {
            return m.CreatedDate;
        }
        Datetime gmtMidnight = Datetime.newInstanceGmt(m.RES_Measurement_From__c, Time.newInstance(0, 0, 0, 0));
        Integer offsetMs = TimeZone.getTimeZone(getOrgTimeZoneId()).getOffset(gmtMidnight);
        return Datetime.newInstance(gmtMidnight.getTime() - offsetMs);
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
        List<RES_Measurement__c> allMeasurements = new RES_MeasurementDAOLayer().getMeasurementsForActiveSync(productIds);

        // productId -> measurement type -> the single measurement in effect (all types, DIR-1797 Active flag)
        Map<Id, Map<String, RES_Measurement__c>> winners = new Map<Id, Map<String, RES_Measurement__c>>();
        for (RES_Measurement__c m : allMeasurements) {
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

        updateActiveFlags(allMeasurements, winners);
        updateProducts(productIds, winners);
    }

    /** Sets RES_Active__c = true on each winner and false on every other measurement; only changed rows are updated. */
    private static void updateActiveFlags(List<RES_Measurement__c> allMeasurements, Map<Id, Map<String, RES_Measurement__c>> winners) {
        List<RES_Measurement__c> toUpdate = new List<RES_Measurement__c>();
        for (RES_Measurement__c m : allMeasurements) {
            Map<String, RES_Measurement__c> byType = winners.get(m.RES_Product__c);
            RES_Measurement__c winner = byType == null ? null : byType.get(m.RES_Measurement_Type__c);
            Boolean shouldBeActive = winner != null && winner.Id == m.Id;
            if (m.RES_Active__c != shouldBeActive) {
                toUpdate.add(new RES_Measurement__c(Id = m.Id, RES_Active__c = shouldBeActive));
            }
        }
        saveAll(toUpdate, 'RES_Measurement__c');
    }

    /** Copies the winning value of each tracked type onto Product2 (clears the field when there is no winner). */
    private static void updateProducts(Set<Id> productIds, Map<Id, Map<String, RES_Measurement__c>> winners) {
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
        saveAll(toUpdate, 'Product2');
    }

    /** Partial success: one failing row must not roll back the user's own save. */
    private static void saveAll(List<SObject> records, String label) {
        if (records.isEmpty()) {
            return;
        }
        for (Database.SaveResult sr : Database.update(records, false)) {
            if (!sr.isSuccess()) {
                System.debug(LoggingLevel.ERROR, '### [RES_ProductMeasurementSyncService] ' + label + ' update failed: ' + sr.getErrors()[0].getMessage());
            }
        }
    }

    @TestVisible
    private static Boolean isActive(RES_Measurement__c m, Date today) {
        return (m.RES_Measurement_From__c == null || m.RES_Measurement_From__c <= today)
            && (m.RES_Measurement_To__c == null || m.RES_Measurement_To__c >= today);
    }

    /** Latest effective start wins (From date start-of-day, or created moment when From is blank), then latest CreatedDate, then higher Id. */
    private static Boolean isBetter(RES_Measurement__c candidate, RES_Measurement__c current) {
        Datetime candStart = effectiveStart(candidate);
        Datetime currStart = effectiveStart(current);
        if (candStart != currStart) {
            return candStart > currStart;
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
