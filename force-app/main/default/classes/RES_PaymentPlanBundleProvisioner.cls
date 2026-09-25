/**
 * ==============================================================================
 * Class Name    : RES_PaymentPlanBundleProvisioner
 * Description   : DIR-1258 Solution Design bullet 6. Invoked as an Action step
 *                  from the final CFO-approve stage of
 *                  RES_Payment_Plan_New_Submission_Approval_Process. For a
 *                  newly-approved Payment Plan that is tagged to a catalog
 *                  (RES_Business_Entity__c), ensures every active Unit under that
 *                  catalog has:
 *                    1. A "Payment Plan" ProductComponentGroup (created once
 *                       per Unit, reused for every Payment Plan approved
 *                       against that catalog - a Unit offers one Payment
 *                       Plan *choice* with potentially several options).
 *                    2. A ProductRelatedComponent child option linking that
 *                       group to this specific Payment Plan product.
 *
 * Framework Rule:
 *      - No SOQL/DML directly against unrelated objects without a DAO.
 *      - Query-only DAOs; DML for the new records lives here (this class
 *        plays the "Service" role for this one-off provisioning task -
 *        it is intentionally not split into a separate Controller/Service
 *        pair given its single entry point and narrow scope).
 * ==============================================================================
 */
public without sharing class RES_PaymentPlanBundleProvisioner {

    private static final String GROUP_NAME = 'Payment Plan';
    private static final String GROUP_CODE_SUFFIX = '-PP';
    private static final Integer GROUP_SEQUENCE = 10;
    private static final Integer GROUP_MIN_COMPONENTS = 1;
    private static final Integer GROUP_MAX_COMPONENTS = 1;
    private static final String RELATIONSHIP_TYPE_NAME = 'Bundle to Bundle Component Relationship';

    private static final RES_Product2DAOLayer PRODUCT_DAO = new RES_Product2DAOLayer();
    private static final RES_ProductComponentGroupDAOLayer GROUP_DAO = new RES_ProductComponentGroupDAOLayer();
    private static final RES_ProductRelatedComponentDAOLayer COMPONENT_DAO = new RES_ProductRelatedComponentDAOLayer();
    private static final RES_ProductRelationshipTypeDAOLayer RELATIONSHIP_TYPE_DAO = new RES_ProductRelationshipTypeDAOLayer();

    public class Request {
        @InvocableVariable(required=true label='Payment Plan Product2 Id')
        public Id paymentPlanId;
    }

    @InvocableMethod(
        label='Provision Payment Plan Bundle Components'
        category='Payment Plan'
        description='DIR-1258: On final approval of a new Payment Plan, ensures every active Unit under its catalog has a Payment Plan ProductComponentGroup and a ProductRelatedComponent option for this plan.'
    )
    public static void provision(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> paymentPlanIds = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.paymentPlanId != null) {
                paymentPlanIds.add(req.paymentPlanId);
            }
        }

        for (Id paymentPlanId : paymentPlanIds) {
            provisionForPlan(paymentPlanId);
        }
    }

    private static void provisionForPlan(Id paymentPlanId) {
        Product2 paymentPlan = PRODUCT_DAO.getPaymentPlanById(paymentPlanId);
        if (paymentPlan == null || paymentPlan.RES_Business_Entity__c == null) {
            /*
             * Solution Design bullet 3: a Payment Plan not tagged to a
             * project/catalog is approved but not auto-applied to any
             * units - the Submit screen already warns the user about this.
             */
            return;
        }

        List<Product2> units = PRODUCT_DAO.getUnitsByCatalog(paymentPlan.RES_Business_Entity__c);
        if (units.isEmpty()) {
            return;
        }

        Map<Id, Product2> unitsById = new Map<Id, Product2>(units);
        Set<Id> unitIds = unitsById.keySet();

        Map<Id, ProductComponentGroup> existingGroupByUnitId = mapGroupsByUnit(
            GROUP_DAO.getGroupsByParentProductsAndName(unitIds, GROUP_NAME)
        );

        Set<Id> unitsAlreadyWired = mapUnitIdsFromComponents(
            COMPONENT_DAO.getComponentsByParentProductsAndChild(unitIds, paymentPlanId)
        );

        Id relationshipTypeId = resolveRelationshipTypeId();
        if (relationshipTypeId == null) {
            /*
             * ProductRelationshipTypeId is a required field on
             * ProductRelatedComponent - without it every component insert
             * would fail. Abort rather than attempt doomed DML.
             */
            System.debug(
                'RES_PaymentPlanBundleProvisioner: ProductRelationshipType "' +
                RELATIONSHIP_TYPE_NAME + '" not found - aborting provisioning for Payment Plan ' + paymentPlanId
            );
            return;
        }

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
            /*
             * Revenue Cloud requires every ProductRelatedComponent under a
             * Static bundle parent to have IsDefaultComponent = true -
             * confirmed against the real org: both insert AND a follow-up
             * update to false are rejected with "Child component must be
             * added by default for a Static Parent Product," for the
             * first and any later component alike. So every option this
             * invocable adds simply stays a default component; there is
             * no way to demote earlier ones via Apex DML, and the
             * platform enforces this invariant itself.
             */
            componentsToInsert.add(buildComponent(unitId, componentGroup.Id, paymentPlanId, relationshipTypeId, true, paymentPlan.RES_Price_Option__c));
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

    private static ProductRelatedComponent buildComponent(Id unitId, Id groupId, Id paymentPlanId, Id relationshipTypeId, Boolean isDefaultComponent, String priceOption) {
        return new ProductRelatedComponent(
            ParentProductId = unitId,
            ChildProductId = paymentPlanId,
            ProductComponentGroupId = groupId,
            ProductRelationshipTypeId = relationshipTypeId,
            Quantity = 1,
            IsComponentRequired = false,
            IsDefaultComponent = isDefaultComponent,
            IsQuantityEditable = false,
            DoesBundlePriceIncludeChild = false,
            QuoteVisibility = 'Always',
            /*
             * RES_ResidentialBundlePricingHook reads RES_Price_Option__c off this exact
             * Unit->Payment-Plan relationship to decide which AttributeBasedAdjustment
             * prices the Unit - without it, selecting this Payment Plan silently applies
             * no pricing adjustment at all. Carried over from the Payment Plan Product2's
             * own RES_Price_Option__c (set once, at Payment Plan creation).
             */
            RES_Price_Option__c = priceOption
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
            'RES_PaymentPlanBundleProvisioner: ' + operation +
            ' failed for Unit ' + unitId + ' - ' + String.join(messages, '; ')
        );
    }
}