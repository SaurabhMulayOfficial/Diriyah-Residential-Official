/**
 * ==============================================================================
 * Class Name    : RES_PaymentPlanExpiryService
 * Description   : Removes expired Payment Plans from the Units they are tagged to.
 *                  A Payment Plan is expired when its RES_Validity_End_Date__c is
 *                  before today. For each affected Unit, inside its "Payment Plan"
 *                  ProductComponentGroup:
 *                    1. An expired component that is the Unit's default is first
 *                       set to IsDefaultComponent = false.
 *                    2. If that leaves the Unit without a default, the first
 *                       remaining component (active, not expired; ordered by
 *                       CreatedDate, Id) is promoted to default, so the Unit
 *                       never ends up without one while other options exist.
 *                    3. The expired component is deleted. Hiding it with
 *                       QuoteVisibility = Never / inactive was not enough - the
 *                       option still showed up on the Unit - so it is removed.
 *
 *                  If the promotion update fails for a Unit, that Unit's expired
 *                  components are kept so the next run retries. A failed demotion
 *                  (e.g. a Static parent rejects IsDefaultComponent = false) does
 *                  not block the delete.
 *
 * Framework Rule:
 *      - No SOQL directly against other objects without a DAO.
 *      - DML for the changed records lives here (Service role).
 * ==============================================================================
 */
public without sharing class RES_PaymentPlanExpiryService {

    private static final RES_ProductRelatedComponentDAOLayer COMPONENT_DAO = new RES_ProductRelatedComponentDAOLayer();

    /**
     * All DML goes through this gateway so tests can force the failure branches, which real data
     * cannot trigger reliably. Production always uses the default implementation.
     */
    @TestVisible
    public virtual class DmlGateway {
        public virtual List<Database.SaveResult> updateRecords(List<SObject> records) {
            return Database.update(records, false, AccessLevel.SYSTEM_MODE);
        }
        public virtual List<Database.DeleteResult> deleteRecords(List<SObject> records) {
            return Database.delete(records, false, AccessLevel.SYSTEM_MODE);
        }
    }

    @TestVisible
    private static DmlGateway dml = new DmlGateway();

    public class Result {
        public Integer unitsProcessed = 0;
        public Integer componentsDeleted = 0;
        public Integer defaultsDemoted = 0;
        public Integer defaultsPromoted = 0;
        public Integer failures = 0;

        public void add(Result other) {
            unitsProcessed += other.unitsProcessed;
            componentsDeleted += other.componentsDeleted;
            defaultsDemoted += other.defaultsDemoted;
            defaultsPromoted += other.defaultsPromoted;
            failures += other.failures;
        }
    }

    public static Date today() {
        return Date.today();
    }

    /**
     * @param unitIds Units whose Payment Plan group should be cleaned up.
     * @param asOf    Plans with a validity end date before this date are expired.
     * @param dryRun  When true, only logs what would change; no DML.
     */
    public static Result process(Set<Id> unitIds, Date asOf, Boolean dryRun) {
        Result result = new Result();
        if (unitIds == null || unitIds.isEmpty() || asOf == null) {
            return result;
        }

        Map<Id, List<ProductRelatedComponent>> componentsByUnit = new Map<Id, List<ProductRelatedComponent>>();
        for (ProductRelatedComponent component : COMPONENT_DAO.getGroupComponentsByUnits(unitIds, RES_PaymentPlanBundleProvisioner.GROUP_NAME)) {
            if (!componentsByUnit.containsKey(component.ParentProductId)) {
                componentsByUnit.put(component.ParentProductId, new List<ProductRelatedComponent>());
            }
            componentsByUnit.get(component.ParentProductId).add(component);
        }

        List<ProductRelatedComponent> toUpdate = new List<ProductRelatedComponent>();
        Map<Id, Id> promotionUnitByComponentId = new Map<Id, Id>();
        Map<Id, List<ProductRelatedComponent>> deletesByUnit = new Map<Id, List<ProductRelatedComponent>>();

        for (Id unitId : componentsByUnit.keySet()) {
            List<ProductRelatedComponent> expired = new List<ProductRelatedComponent>();
            ProductRelatedComponent firstCandidate = null;
            Boolean expiredWasDefault = false;
            Boolean remainingHasDefault = false;

            for (ProductRelatedComponent component : componentsByUnit.get(unitId)) {
                if (isExpired(component, asOf)) {
                    expired.add(component);
                    if (component.IsDefaultComponent) {
                        expiredWasDefault = true;
                    }
                    continue;
                }
                if (component.IsDefaultComponent) {
                    remainingHasDefault = true;
                } else if (firstCandidate == null && component.ChildProduct.IsActive) {
                    firstCandidate = component;
                }
            }

            if (expired.isEmpty()) {
                continue;
            }
            result.unitsProcessed++;
            deletesByUnit.put(unitId, expired);

            for (ProductRelatedComponent component : expired) {
                if (component.IsDefaultComponent) {
                    toUpdate.add(new ProductRelatedComponent(Id = component.Id, IsDefaultComponent = false));
                    result.defaultsDemoted++;
                }
            }
            if (expiredWasDefault && !remainingHasDefault && firstCandidate != null) {
                toUpdate.add(new ProductRelatedComponent(Id = firstCandidate.Id, IsDefaultComponent = true));
                promotionUnitByComponentId.put(firstCandidate.Id, unitId);
                result.defaultsPromoted++;
            }
        }

        Set<Id> failedUnits = new Set<Id>();
        if (!dryRun && !toUpdate.isEmpty()) {
            Database.SaveResult[] saveResults = dml.updateRecords(toUpdate);
            for (Integer index = 0; index < saveResults.size(); index++) {
                if (!saveResults[index].isSuccess()) {
                    /*
                     * A failed demotion is harmless (the component is deleted anyway; a Static
                     * parent rejects IsDefaultComponent = false). A failed promotion would leave
                     * the Unit without a default, so that Unit's deletes are held back for retry.
                     */
                    if (promotionUnitByComponentId.containsKey(toUpdate[index].Id)) {
                        failedUnits.add(promotionUnitByComponentId.get(toUpdate[index].Id));
                    }
                    result.failures++;
                    logFailure('default flag update', toUpdate[index].Id, saveResults[index].getErrors());
                }
            }
        }

        List<ProductRelatedComponent> toDelete = new List<ProductRelatedComponent>();
        for (Id unitId : deletesByUnit.keySet()) {
            if (failedUnits.contains(unitId)) {
                continue;
            }
            for (ProductRelatedComponent component : deletesByUnit.get(unitId)) {
                toDelete.add(component);
                System.debug(
                    'RES_PaymentPlanExpiryService: ' + (dryRun ? '[DRY RUN] would delete' : 'deleting') +
                    ' PRC ' + component.Id + ' - Unit ' + unitId + ', Payment Plan ' + component.ChildProductId +
                    ' (' + component.ChildProduct.Name + '), validity end ' + component.ChildProduct.RES_Validity_End_Date__c +
                    ', was default ' + component.IsDefaultComponent
                );
            }
        }

        if (dryRun) {
            result.componentsDeleted = toDelete.size();
            return result;
        }

        if (!toDelete.isEmpty()) {
            Database.DeleteResult[] deleteResults = dml.deleteRecords(toDelete);
            for (Integer index = 0; index < deleteResults.size(); index++) {
                if (deleteResults[index].isSuccess()) {
                    result.componentsDeleted++;
                } else {
                    result.failures++;
                    logFailure('component delete', toDelete[index].Id, deleteResults[index].getErrors());
                }
            }
        }
        return result;
    }

    private static Boolean isExpired(ProductRelatedComponent component, Date asOf) {
        Date validityEnd = component.ChildProduct.RES_Validity_End_Date__c;
        return validityEnd != null && validityEnd < asOf;
    }

    private static void logFailure(String operation, Id componentId, List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getMessage());
        }
        System.debug(
            LoggingLevel.ERROR,
            'RES_PaymentPlanExpiryService: ' + operation + ' failed for PRC ' + componentId + ' - ' + String.join(messages, '; ')
        );
    }
}
