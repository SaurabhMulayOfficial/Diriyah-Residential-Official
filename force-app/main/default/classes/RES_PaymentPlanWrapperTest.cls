@isTest
private class RES_PaymentPlanWrapperTest {

    private static String buildJson() {
        return '{' +
            '"Change_Indicator": "U",' +
            '"RES_Product_External_ID": "PP-001",' +
            '"ProductName": "Standard Plan",' +
            '"RES_No_of_Years": 5,' +
            '"AvailabilityDate": "2024-01-01",' +
            '"DiscontinuedDate": "2029-01-01",' +
            '"RES_Approval_Status": "Approved",' +
            '"RES_Status_Role_description": "CFO",' +
            '"RES_Status_Role": "Z_CFO",' +
            '"RES_Note": "Test note",' +
            '"RES_No_of_Months": 60,' +
            '"RES_Review": "Reviewed",' +
            '"RES_DSOP_NOTE": "DSOP",' +
            '"RES_SLSD_NOTE": "SLSD",' +
            '"RES_CDO_NOTE": "CDO",' +
            '"RES_CFO_NOTE": "CFO",' +
            '"RES_Z_TIME": "120000",' +
            '"RES_Z_DATE": "2024-01-01",' +
            '"RES_Z_ERNAM": "ERNAM",' +
            '"RES_Z_RBEAR": "RBEAR",' +
            '"RES_Z_DBEAR": "DBEAR",' +
            '"RES_Z_TBEAR": "TBEAR",' +
            '"RES_CustomFields": [{"name": "field1", "value": "val1"}],' +
            '"RES_Plan_Installments": [{' +
                '"Change_Indicator": "I",' +
                '"RES_Product_External_ID": "PP-001",' +
                '"RES_Sequence": 1,' +
                '"RES_Installment_Payment_Type": "Booking",' +
                '"Name": "Installment 1",' +
                '"RES_Installment_Percentage": 10.5,' +
                '"RES_POC_Percentage": 5.0,' +
                '"RES_Installment_Amount": 50000,' +
                '"Condition_Months": 3,' +
                '"Condition_Days": 15' +
            '}],' +
            '"RES_Payment_Plan_Assignments": [{' +
                '"Change_Indicator": "I",' +
                '"RES_Product_External_ID": "PP-001",' +
                '"RES_Business_Entity": "BE001",' +
                '"RES_Construction_Phase": "Phase1",' +
                '"RES_Project": "PROJ001",' +
                '"RES_UnitId": "UNIT-001",' +
                '"Company_Code": "1000"' +
            '}]' +
        '}';
    }

    @isTest
    static void testParse() {
        RES_PaymentPlanWrapper wrapper = RES_PaymentPlanWrapper.parse(buildJson());

        System.assertEquals('U', wrapper.Change_Indicator);
        System.assertEquals('PP-001', wrapper.RES_Product_External_ID);
        System.assertEquals('Standard Plan', wrapper.ProductName);
        System.assertEquals(5, wrapper.RES_No_of_Years);
        System.assertEquals('2024-01-01', wrapper.AvailabilityDate);
        System.assertEquals('2029-01-01', wrapper.DiscontinuedDate);
        System.assertEquals('Approved', wrapper.RES_Approval_Status);
        System.assertEquals('CFO', wrapper.RES_Status_Role_description);
        System.assertEquals('Z_CFO', wrapper.RES_Status_Role);
        System.assertEquals('Test note', wrapper.RES_Note);
        System.assertEquals(60, wrapper.RES_No_of_Months);
        System.assertEquals('Reviewed', wrapper.RES_Review);
        System.assertEquals('DSOP', wrapper.RES_DSOP_NOTE);
        System.assertEquals('SLSD', wrapper.RES_SLSD_NOTE);
        System.assertEquals('CDO', wrapper.RES_CDO_NOTE);
        System.assertEquals('CFO', wrapper.RES_CFO_NOTE);
        System.assertEquals('120000', wrapper.RES_Z_TIME);
        System.assertEquals('2024-01-01', wrapper.RES_Z_DATE);
        System.assertEquals('ERNAM', wrapper.RES_Z_ERNAM);
        System.assertEquals('RBEAR', wrapper.RES_Z_RBEAR);
        System.assertEquals('DBEAR', wrapper.RES_Z_DBEAR);
        System.assertEquals('TBEAR', wrapper.RES_Z_TBEAR);
    }

    @isTest
    static void testCustomFields() {
        RES_PaymentPlanWrapper wrapper = RES_PaymentPlanWrapper.parse(buildJson());

        System.assertNotEquals(null, wrapper.RES_CustomFields);
        System.assertEquals(1, wrapper.RES_CustomFields.size());
        System.assertEquals('field1', wrapper.RES_CustomFields[0].name);
        System.assertEquals('val1', wrapper.RES_CustomFields[0].value);
    }

    @isTest
    static void testPlanInstallments() {
        RES_PaymentPlanWrapper wrapper = RES_PaymentPlanWrapper.parse(buildJson());

        System.assertNotEquals(null, wrapper.RES_Plan_Installments);
        System.assertEquals(1, wrapper.RES_Plan_Installments.size());

        RES_PaymentPlanWrapper.PlanInstallment inst = wrapper.RES_Plan_Installments[0];
        System.assertEquals('I', inst.Change_Indicator);
        System.assertEquals('PP-001', inst.RES_Product_External_ID);
        System.assertEquals(1, inst.RES_Sequence);
        System.assertEquals('Booking', inst.RES_Installment_Payment_Type);
        System.assertEquals('Installment 1', inst.Name);
        System.assertEquals(10.5, inst.RES_Installment_Percentage);
        System.assertEquals(5.0, inst.RES_POC_Percentage);
        System.assertEquals(50000, inst.RES_Installment_Amount);
        System.assertEquals(3, inst.Condition_Months);
        System.assertEquals(15, inst.Condition_Days);
    }

    @isTest
    static void testPaymentPlanAssignments() {
        RES_PaymentPlanWrapper wrapper = RES_PaymentPlanWrapper.parse(buildJson());

        System.assertNotEquals(null, wrapper.RES_Payment_Plan_Assignments);
        System.assertEquals(1, wrapper.RES_Payment_Plan_Assignments.size());

        RES_PaymentPlanWrapper.PaymentPlanAssignment assign = wrapper.RES_Payment_Plan_Assignments[0];
        System.assertEquals('I', assign.Change_Indicator);
        System.assertEquals('PP-001', assign.RES_Product_External_ID);
        System.assertEquals('BE001', assign.RES_Business_Entity);
        System.assertEquals('Phase1', assign.RES_Construction_Phase);
        System.assertEquals('PROJ001', assign.RES_Project);
        System.assertEquals('UNIT-001', assign.RES_UnitId);
        System.assertEquals('1000', assign.Company_Code);
    }

    @isTest
    static void testParseNullLists() {
        String json = '{"Change_Indicator":"I","RES_Product_External_ID":"PP-002"}';
        RES_PaymentPlanWrapper wrapper = RES_PaymentPlanWrapper.parse(json);

        System.assertEquals('I', wrapper.Change_Indicator);
        System.assertEquals('PP-002', wrapper.RES_Product_External_ID);
        System.assertEquals(null, wrapper.RES_CustomFields);
        System.assertEquals(null, wrapper.RES_Plan_Installments);
        System.assertEquals(null, wrapper.RES_Payment_Plan_Assignments);
    }
}
