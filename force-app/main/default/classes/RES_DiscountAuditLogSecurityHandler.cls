/**
 * Class Name     : RES_DiscountAuditLogSecurityHandler
 * Description    : DIR-871: Discount Audit Log records are immutable. Delete is blocked for every
 *                  user, including System Administrators - this cannot be enforced declaratively
 *                  since validation rules do not fire on delete.
 */
public with sharing class RES_DiscountAuditLogSecurityHandler extends RES_BaseTriggerHandler {
    protected override void beforeDelete() {
        for (RES_Discount_Audit_Log__c log : (List<RES_Discount_Audit_Log__c>) Trigger.old) {
            log.addError('Discount Audit Log records are immutable and cannot be deleted.');
        }
    }
}
