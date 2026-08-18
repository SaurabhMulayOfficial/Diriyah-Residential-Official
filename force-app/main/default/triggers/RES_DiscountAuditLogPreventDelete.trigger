/**
 * Trigger Name   : RES_DiscountAuditLogPreventDelete
 * Description    : DIR-871: Delete is blocked on Discount Audit Log for every user.
 *                  RES_DiscountAuditLogSecurityHandler handles beforeDelete.
 */
trigger RES_DiscountAuditLogPreventDelete on RES_Discount_Audit_Log__c (before delete) {
    new RES_DiscountAuditLogSecurityHandler().run();
}
