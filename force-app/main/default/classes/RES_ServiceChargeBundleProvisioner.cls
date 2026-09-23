/**
 * ==============================================================================
 * Class Name    : RES_ServiceChargeBundleProvisioner
 * Description   : Invoked from RES_UnifiedIngestionEngine whenever the CSV
 *                  ingestion framework creates a new Unit. Ensures the unit
 *                  has:
 *                    1. A "Service Charge" ProductComponentGroup (created
 *                       once per Unit).
 *                    2. A ProductRelatedComponent linking that group to the
 *                       single, shared Service Charge product looked up by
 *                       the ProductCode named in the RES_Service_Charge_Product_Code
 *                       custom label - the same product every Unit uses,
 *                       never created fresh. Resolved by ProductCode rather
 *                       than a stored Id: Salesforce record Ids are
 *                       org-specific, so a hardcoded Id would only resolve
 *                       correctly in the one org it was captured from.
 *                  Mirrors the same bundle-wiring shape used by
 *                  RES_PaymentPlanBundleProvisioner (DIR-1258) and the
 *                  reference "Wadi Safar Top Unit" / "RES Test Unit A/B/C"
 *                  products already in the org.
 *
 * Framework Rule:
 *      - No SOQL/DML directly against unrelated objects without a DAO.
 *      - Query-only DAOs; DML for the new records lives here (same
 *        Controller/Service split RES_PaymentPlanBundleProvisioner uses).
 * ==============================================================================
 */
public without sharing class RES_ServiceChargeBundleProvisioner {

    private static final String GROUP_NAME = 'Service Charge';
    private static final String GROUP_CODE_SUFFIX = '-SC';
    private static final Integer GROUP_SEQUENCE = 100;
    private static final Integer GROUP_MIN_COMPONENTS = 1;
    private static final Integer GROUP_MAX_COMPONENTS = 1;
    private static final String RELATIONSHIP_TYPE_NAME = 'Bundle to Bundle Component Relationship';

    private static final RES_Product2DAOLayer PRODUCT_DAO = new RES_Product2DAOLayer();
    private static final RES_ProductComponentGroupDAOLayer GROUP_DAO = new RES_ProductComponentGroupDAOLayer();
    private static final RES_ProductRelatedComponentDAOLayer COMPONENT_DAO = new RES_ProductRelatedComponentDAOLayer();
    private static final RES_ProductRelationshipTypeDAOLayer RELATIONSHIP_TYPE_DAO = new RES_ProductRelationshipTypeDAOLayer();

    public static void provisionForUnits(Set<Id> unitIds) {
        if (unitIds == null || unitIds.isEmpty()) {
            return;
        }

        Id serviceChargeId = resolveServiceChargeProductId();
        if (serviceChargeId == null) {
            /*
             * RES_Service_Charge_Product_Code is blank, or no active Product2
             * in this org carries that ProductCode - nothing to wire up.
             * Abort rather than attempt doomed DML.
             */
            System.debug(
                'RES_ServiceChargeBundleProvisioner: no Product2 found for ProductCode "' +
                System.Label.RES_Service_Charge_Product_Code + '" - skipping Service Charge provisioning.'
            );
            return;
        }

        Id relationshipTypeId = resolveRelationshipTypeId();
        if (relationshipTypeId == null) {
            /*
             * ProductRelationshipTypeId is a required field on
             * ProductRelatedComponent - without it every component insert
             * would fail. Abort rather than attempt doomed DML.
             */
            System.debug(
                'RES_ServiceChargeBundleProvisioner: ProductRelationshipType "' +
                RELATIONSHIP_TYPE_NAME + '" not found - aborting Service Charge provisioning.'
            );
            return;
        }

        Map<Id, ProductComponentGroup> existingGroupByUnitId = mapGroupsByUnit(
            GROUP_DAO.getGroupsByParentProductsAndName(unitIds, GROUP_NAME)
        );

        Set<Id> unitsAlreadyWired = mapUnitIdsFromComponents(
            COMPONENT_DAO.getComponentsByParentProductsAndChild(unitIds, serviceChargeId)
        );

        List<ProductComponentGroup> groupsToInsert = new List<ProductComponentGroup>();
        List<Id> unitIdsForNewGroups = new List<Id>();
        for (Id unitId : unitIds) {
            if (!existingGroupByUnitId.containsKey(unitId)) {
                groupsToInsert.add(buildGroup(unitId));
                unitIdsForNewGroups.add(unitId);
            }
        }

        if (!groupsToInsert.isEmpty()) {
            Database.SaveResult[] groupResults = Database.insert(groupsToInsert, false, AccessLevel.SYSTEM_MODE);
            for (Integer index = 0; index < groupResults.size(); index++) {
                if (groupResults[index].isSuccess()) {
                    existingGroupByUnitId.put(
                        unitIdsForNewGroups[index],
                        new ProductComponentGroup(Id = groupResults[index].getId())
                    );
                } else {
                    logFailure('ProductComponentGroup insert', unitIdsForNewGroups[index], groupResults[index].getErrors());
                }
            }
        }

        List<ProductRelatedComponent> componentsToInsert = new List<ProductRelatedComponent>();
        for (Id unitId : unitIds) {
            if (unitsAlreadyWired.contains(unitId)) {
                continue;
            }
            ProductComponentGroup componentGroup = existingGroupByUnitId.get(unitId);
            if (componentGroup == null) {
                /*
                 * Group insert failed for this unit - skip the component,
                 * already logged above.
                 */
                continue;
            }
            componentsToInsert.add(buildComponent(unitId, componentGroup.Id, serviceChargeId, relationshipTypeId));
        }

        if (!componentsToInsert.isEmpty()) {
            Database.SaveResult[] componentResults = Database.insert(componentsToInsert, false, AccessLevel.SYSTEM_MODE);
            for (Integer index = 0; index < componentResults.size(); index++) {
                if (!componentResults[index].isSuccess()) {
                    logFailure('ProductRelatedComponent insert', componentsToInsert[index].ParentProductId, componentResults[index].getErrors());
                }
            }
        }
    }

    private static Id resolveServiceChargeProductId() {
        String code = System.Label.RES_Service_Charge_Product_Code;
        if (String.isBlank(code)) {
            return null;
        }
        List<Product2> found = PRODUCT_DAO.getProductsByProductCodes(new Set<String>{ code });
        return found.isEmpty() ? null : found[0].Id;
    }

    private static Id resolveRelationshipTypeId() {
        ProductRelationshipType relationshipType = RELATIONSHIP_TYPE_DAO.getByName(RELATIONSHIP_TYPE_NAME);
        return relationshipType == null ? null : relationshipType.Id;
    }

    private static ProductComponentGroup buildGroup(Id unitId) {
        return new ProductComponentGroup(
            ParentProductId = unitId,
            Name = GROUP_NAME,
            /*
             * Code is enforced globally unique across every
             * ProductComponentGroup in the org (not just per-parent), so
             * it cannot be a shared constant - derive it from the Unit's
             * own Id, which is guaranteed unique.
             */
            Code = unitId + GROUP_CODE_SUFFIX,
            Sequence = GROUP_SEQUENCE,
            MinBundleComponents = GROUP_MIN_COMPONENTS,
            MaxBundleComponents = GROUP_MAX_COMPONENTS
        );
    }

    private static ProductRelatedComponent buildComponent(Id unitId, Id groupId, Id serviceChargeId, Id relationshipTypeId) {
        return new ProductRelatedComponent(
            ParentProductId = unitId,
            ChildProductId = serviceChargeId,
            ProductComponentGroupId = groupId,
            ProductRelationshipTypeId = relationshipTypeId,
            Quantity = 1,
            IsComponentRequired = true,
            IsDefaultComponent = true,
            IsQuantityEditable = false,
            DoesBundlePriceIncludeChild = false,
            QuoteVisibility = 'Always',
            QuantityScaleMethod = 'Proportional',
            Sequence = GROUP_SEQUENCE
        );
    }

    private static Map<Id, ProductComponentGroup> mapGroupsByUnit(List<ProductComponentGroup> groups) {
        Map<Id, ProductComponentGroup> result = new Map<Id, ProductComponentGroup>();
        for (ProductComponentGroup componentGroup : groups) {
            result.put(componentGroup.ParentProductId, componentGroup);
        }
        return result;
    }

    private static Set<Id> mapUnitIdsFromComponents(List<ProductRelatedComponent> components) {
        Set<Id> result = new Set<Id>();
        for (ProductRelatedComponent component : components) {
            result.add(component.ParentProductId);
        }
        return result;
    }

    private static void logFailure(String operation, Id unitId, List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getMessage());
        }
        System.debug(
            'RES_ServiceChargeBundleProvisioner: ' + operation +
            ' failed for Unit ' + unitId + ' - ' + String.join(messages, '; ')
        );
    }
}
