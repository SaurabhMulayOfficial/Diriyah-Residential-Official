/**
 * @description Daily job. A Payment Plan expiring on its RES_Validity_End_Date__c involves no record save, so no
 *              trigger or flow sees it. This batch finds Unit-level Payment Plan components whose plan has expired
 *              and hands their Units to RES_PaymentPlanExpiryService, which demotes/promotes the default component
 *              and deletes the expired components.
 *
 *              Schedule daily:  System.schedule('Payment Plan Expiry', '0 0 1 * * ?', new RES_PaymentPlanExpiryBatch());
 *              Dry run (logs only, no DML):  Database.executeBatch(new RES_PaymentPlanExpiryBatch(true), 200);
 *              Delegates to RES_PaymentPlanExpiryService.
 */
public without sharing class RES_PaymentPlanExpiryBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    private static final Integer BATCH_SIZE = 200;

    private final Boolean dryRun;
    private final RES_ProductRelatedComponentDAOLayer componentDao = new RES_ProductRelatedComponentDAOLayer();
    private final RES_PaymentPlanExpiryService.Result totals = new RES_PaymentPlanExpiryService.Result();

    public RES_PaymentPlanExpiryBatch() {
        this(false);
    }

    public RES_PaymentPlanExpiryBatch(Boolean dryRun) {
        this.dryRun = dryRun == true;
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new RES_PaymentPlanExpiryBatch(dryRun), BATCH_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return componentDao.getExpiredPaymentPlanComponentsLocator(
            RES_PaymentPlanExpiryService.today(),
            RES_PaymentPlanBundleProvisioner.GROUP_NAME
        );
    }

    public void execute(Database.BatchableContext bc, List<ProductRelatedComponent> scope) {
        Set<Id> unitIds = new Set<Id>();
        for (ProductRelatedComponent component : scope) {
            unitIds.add(component.ParentProductId);
        }
        totals.add(RES_PaymentPlanExpiryService.process(unitIds, RES_PaymentPlanExpiryService.today(), dryRun));
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(
            'RES_PaymentPlanExpiryBatch finished' + (dryRun ? ' [DRY RUN]' : '') +
            ': units=' + totals.unitsProcessed + ', deleted=' + totals.componentsDeleted +
            ', demoted=' + totals.defaultsDemoted + ', promoted=' + totals.defaultsPromoted +
            ', failures=' + totals.failures
        );
    }
}
