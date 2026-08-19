/**
 * Class Name     : RES_DiscountAuditLogSecurityHandlerTest
 * Description    : DIR-871: Test class for RES_DiscountAuditLogSecurityHandler - verifies
 *                  Discount Audit Log records cannot be deleted by any user, including
 *                  System Administrators.
 */
@isTest
public class RES_DiscountAuditLogSecurityHandlerTest {

    @isTest
    public static void testDeleteIsBlocked() {
        User adminUser = RES_TestDataFactory.createSystemAdminUser();

        System.runAs(adminUser) {
            Account acc = RES_TestDataFactory.createCompanyRTAccount('Globant', '9898989898');
            Opportunity opp = RES_TestDataFactory.createSingleBuyerOpportunity(
                'Globant', acc.Id, 'Proposal', Date.Today(), 'Amansamar Residences Wadi Safar'
            );
            Id quoteRecordTypeId = Schema.SObjectType.Quote
                .getRecordTypeInfosByDeveloperName()
                .get(System.Label.RES_Quote_Residential_Sales_RT)
                .getRecordTypeId();
            Quote quoteObj = RES_TestDataFactory.createQuote(
                'Test Quote', opp.Id, Test.getStandardPricebookId(), 'Negotiating', quoteRecordTypeId
            );

            // RES_Entry_Type_Locked only allows a non-automated user to insert a
            // Correction entry, and RES_DAL_Correction_Restricted requires a Reason -
            // this test is exercising delete-immutability, not submission creation,
            // so a Correction entry is the only type a test-context user can insert.
            RES_Discount_Audit_Log__c logEntry = new RES_Discount_Audit_Log__c(
                RES_Quote__c = quoteObj.Id,
                RES_Entry_Type__c = 'Correction',
                RES_Discount_Requested__c = 8,
                RES_Reason__c = 'Test justification for delete-immutability test.'
            );
            insert logEntry;

            Test.startTest();
            Boolean deleteBlocked = false;
            try {
                delete logEntry;
            } catch (DmlException e) {
                deleteBlocked = e.getMessage().contains('Discount Audit Log records are immutable');
            }
            Test.stopTest();

            System.assert(deleteBlocked, 'Deleting a Discount Audit Log record should be blocked.');
            System.assertNotEquals(
                null, new RES_DiscountAuditLogDAO().getById(logEntry.Id),
                'The Discount Audit Log record should still exist.'
            );
        }
    }
}
