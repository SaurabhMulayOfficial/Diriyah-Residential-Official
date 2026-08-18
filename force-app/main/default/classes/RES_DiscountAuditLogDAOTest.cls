/**
 * Class Name     : RES_DiscountAuditLogDAOTest
 * Description    : DIR-871: Test class for RES_DiscountAuditLogDAO.
 */
@isTest
public class RES_DiscountAuditLogDAOTest {

    @isTest
    public static void testGetById() {
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

        RES_Discount_Audit_Log__c logEntry = new RES_Discount_Audit_Log__c(
            RES_Quote__c = quoteObj.Id,
            RES_Entry_Type__c = 'Submission',
            RES_Discount_Requested__c = 8
        );
        insert logEntry;

        Test.startTest();
        RES_Discount_Audit_Log__c result = new RES_DiscountAuditLogDAO().getById(logEntry.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'A record should be returned for a valid Id.');
        System.assertEquals(logEntry.Id, result.Id, 'The returned record should match the queried Id.');
        System.assertEquals(quoteObj.Id, result.RES_Quote__c, 'The Quote lookup should be populated.');
    }

    @isTest
    public static void testGetByIdReturnsNullWhenNotFound() {
        Test.startTest();
        RES_Discount_Audit_Log__c result = new RES_DiscountAuditLogDAO().getById(
            RES_Discount_Audit_Log__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA'
        );
        Test.stopTest();

        System.assertEquals(null, result, 'No record should be returned for a non-existent Id.');
    }
}
