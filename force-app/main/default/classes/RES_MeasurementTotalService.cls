/**
 * @description Calculates total measurements (e.g. Y020 Total Internal Area) from their component measurements,
 *              as configured in RES_Measurement_Total_Rule__mdt. A total can itself be a component of another
 *              total (Y020 -> Y040 -> Y055); totals are always rebuilt from the leaf components.
 *
 *              Only the active component of each type (the RES_Active__c winner) is summed; a missing component counts as 0.
 *              One total record per product and total type is kept active: amount = sum, From = latest component From,
 *              To = earliest component To. When no component of a total is active, its records are deactivated (not deleted).
 *              Total types are never sent to SAP (see isTotalType usages).
 *
 *              Called from: RES_ProductMeasurementSyncService.syncProducts (trigger path and daily batch path)
 */
public without sharing class RES_MeasurementTotalService {

    // Same open-ended To that RES_MeasurementServices.setMeasurementDefaults stamps on insert
    private static final Date DEFAULT_TO = Date.newInstance(2099, 12, 31);

    @TestVisible
    private static List<RES_Measurement_Total_Rule__mdt> rules;
    private static Map<String, Set<String>> componentsByTotal;
    private static Map<String, String> typeLabels;

    /** Total type -> its direct component types (active rules only). */
    private static Map<String, Set<String>> getComponentsByTotal() {
        if (componentsByTotal == null) {
            if (rules == null) {
                rules = RES_Measurement_Total_Rule__mdt.getAll().values();
            }
            componentsByTotal = new Map<String, Set<String>>();
            for (RES_Measurement_Total_Rule__mdt rule : rules) {
                if (rule.RES_Active__c != true || String.isBlank(rule.RES_Component_Type__c) || String.isBlank(rule.RES_Total_Type__c)) {
                    continue;
                }
                String totalType = rule.RES_Total_Type__c.trim();
                if (!componentsByTotal.containsKey(totalType)) {
                    componentsByTotal.put(totalType, new Set<String>());
                }
                componentsByTotal.get(totalType).add(rule.RES_Component_Type__c.trim());
            }
        }
        return componentsByTotal;
    }

    public static Set<String> getTotalTypes() {
        return getComponentsByTotal().keySet();
    }

    public static Boolean isTotalType(String measurementType) {
        return String.isNotBlank(measurementType) && getTotalTypes().contains(measurementType);
    }

    /**
     * @description Creates/updates the total records of the given products and sets RES_Active__c on every total-type record.
     * @param productIds      products to recalculate
     * @param allMeasurements every measurement of those products (RES_MeasurementDAOLayer.getMeasurementsForActiveSync)
     * @param winners         productId -> measurement type -> the active measurement of that type
     */
    public static void syncTotals(Set<Id> productIds, List<RES_Measurement__c> allMeasurements, Map<Id, Map<String, RES_Measurement__c>> winners) {
        if (productIds == null || productIds.isEmpty() || getTotalTypes().isEmpty()) {
            return;
        }

        // productId -> total type -> existing total records
        Map<Id, Map<String, List<RES_Measurement__c>>> existingTotals = new Map<Id, Map<String, List<RES_Measurement__c>>>();
        for (RES_Measurement__c m : allMeasurements) {
            if (!isTotalType(m.RES_Measurement_Type__c)) {
                continue;
            }
            if (!existingTotals.containsKey(m.RES_Product__c)) {
                existingTotals.put(m.RES_Product__c, new Map<String, List<RES_Measurement__c>>());
            }
            Map<String, List<RES_Measurement__c>> byType = existingTotals.get(m.RES_Product__c);
            if (!byType.containsKey(m.RES_Measurement_Type__c)) {
                byType.put(m.RES_Measurement_Type__c, new List<RES_Measurement__c>());
            }
            byType.get(m.RES_Measurement_Type__c).add(m);
        }

        List<RES_Measurement__c> toInsert = new List<RES_Measurement__c>();
        List<RES_Measurement__c> toUpdate = new List<RES_Measurement__c>();

        for (Id productId : productIds) {
            Map<String, RES_Measurement__c> active = winners.containsKey(productId)
                ? winners.get(productId) : new Map<String, RES_Measurement__c>();
            Map<String, List<RES_Measurement__c>> existingByType = existingTotals.containsKey(productId)
                ? existingTotals.get(productId) : new Map<String, List<RES_Measurement__c>>();
            Map<String, Total> memo = new Map<String, Total>();

            for (String totalType : getTotalTypes()) {
                Total calc = calculate(totalType, active, memo, new Set<String>());
                List<RES_Measurement__c> existing = existingByType.containsKey(totalType)
                    ? existingByType.get(totalType) : new List<RES_Measurement__c>();
                RES_Measurement__c keep = calc.hasComponents ? pickRecordToKeep(existing) : null;

                if (calc.hasComponents) {
                    if (keep == null) {
                        toInsert.add(new RES_Measurement__c(
                            Name = getTypeLabel(totalType),
                            RES_Product__c = productId,
                            RES_Measurement_Type__c = totalType,
                            RES_Measurement_Amount__c = calc.amount,
                            RES_Unit_Of_Measurement__c = calc.uom,
                            RES_Measurement_From__c = calc.fromDate,
                            RES_Measurement_To__c = calc.toDate,
                            RES_Active__c = true
                        ));
                    } else if (isDifferent(keep, calc)) {
                        toUpdate.add(new RES_Measurement__c(
                            Id = keep.Id,
                            RES_Measurement_Amount__c = calc.amount,
                            RES_Unit_Of_Measurement__c = calc.uom,
                            RES_Measurement_From__c = calc.fromDate,
                            RES_Measurement_To__c = calc.toDate,
                            RES_Active__c = true
                        ));
                    }
                }
                for (RES_Measurement__c m : existing) {
                    if ((keep == null || m.Id != keep.Id) && m.RES_Active__c == true) {
                        toUpdate.add(new RES_Measurement__c(Id = m.Id, RES_Active__c = false));
                    }
                }
            }
        }

        save(toInsert, true);
        save(toUpdate, false);
    }

    /** Sums the active leaf components of a total, recursing through component totals. */
    private static Total calculate(String totalType, Map<String, RES_Measurement__c> active, Map<String, Total> memo, Set<String> path) {
        if (memo.containsKey(totalType)) {
            return memo.get(totalType);
        }
        Total result = new Total();
        if (!path.add(totalType)) {
            System.debug(LoggingLevel.ERROR, '### [RES_MeasurementTotalService] Circular total rule at ' + totalType);
            return result;
        }
        for (String componentType : getComponentsByTotal().get(totalType)) {
            if (isTotalType(componentType)) {
                result.add(calculate(componentType, active, memo, path));
            } else if (active.containsKey(componentType)) {
                result.add(active.get(componentType));
            }
        }
        path.remove(totalType);
        memo.put(totalType, result);
        return result;
    }

    /** Prefer the currently active total record, then the most recently created. */
    private static RES_Measurement__c pickRecordToKeep(List<RES_Measurement__c> existing) {
        RES_Measurement__c keep = null;
        for (RES_Measurement__c m : existing) {
            if (keep == null
                    || (m.RES_Active__c == true && keep.RES_Active__c != true)
                    || (m.RES_Active__c == keep.RES_Active__c && m.CreatedDate > keep.CreatedDate)) {
                keep = m;
            }
        }
        return keep;
    }

    private static Boolean isDifferent(RES_Measurement__c m, Total calc) {
        return m.RES_Active__c != true
            || m.RES_Measurement_Amount__c != calc.amount
            || m.RES_Unit_Of_Measurement__c != calc.uom
            || m.RES_Measurement_From__c != calc.fromDate
            || m.RES_Measurement_To__c != calc.toDate;
    }

    private static String getTypeLabel(String typeCode) {
        if (typeLabels == null) {
            typeLabels = new Map<String, String>();
            for (Schema.PicklistEntry pe : RES_Measurement__c.RES_Measurement_Type__c.getDescribe().getPicklistValues()) {
                typeLabels.put(pe.getValue(), pe.getLabel());
            }
        }
        return (typeLabels.containsKey(typeCode) ? typeLabels.get(typeCode) : typeCode).left(80);
    }

    /** Partial success: one failing row must not roll back the user's own save. */
    private static void save(List<RES_Measurement__c> records, Boolean isInsert) {
        if (records.isEmpty()) {
            return;
        }
        List<Database.SaveResult> results = isInsert ? Database.insert(records, false) : Database.update(records, false);
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                System.debug(LoggingLevel.ERROR, '### [RES_MeasurementTotalService] Total measurement save failed: ' + sr.getErrors()[0].getMessage());
            }
        }
    }

    /** Running total: blank amount counts as 0; validity window is the overlap of all contributing components. */
    private class Total {
        Decimal amount = 0;
        String uom;
        Date fromDate;
        Date toDate;
        Boolean hasComponents = false;

        void add(RES_Measurement__c m) {
            combine(m.RES_Measurement_Amount__c, m.RES_Unit_Of_Measurement__c, m.RES_Measurement_From__c, m.RES_Measurement_To__c);
        }

        void add(Total other) {
            if (other.hasComponents) {
                combine(other.amount, other.uom, other.fromDate, other.toDate);
            }
        }

        void combine(Decimal value, String unit, Date validFrom, Date validTo) {
            hasComponents = true;
            amount += value == null ? 0 : value;
            if (String.isBlank(uom)) uom = unit;
            if (validFrom != null && (fromDate == null || validFrom > fromDate)) fromDate = validFrom;
            if (validTo != null && (toDate == null || validTo < toDate)) toDate = validTo;
            if (toDate == null) toDate = DEFAULT_TO;
        }
    }
}
