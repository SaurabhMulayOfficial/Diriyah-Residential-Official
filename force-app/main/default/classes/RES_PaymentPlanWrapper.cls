public class RES_PaymentPlanWrapper {

    public String Change_Indicator;
    public String RES_Product_External_ID;
    public String ProductName;
    public Integer RES_No_of_Years;
    public String AvailabilityDate;
    public String DiscontinuedDate;
    public String RES_Approval_Status;
    public String RES_Status_Role_description;
    public String RES_Status_Role;
    public String RES_Note;
    public Integer RES_No_of_Months;
    public String RES_Review;
    public String RES_DSOP_NOTE;
    public String RES_SLSD_NOTE;
    public String RES_CDO_NOTE;
    public String RES_CFO_NOTE;
    public String RES_Z_TIME;
    public String RES_Z_DATE;
    public String RES_Z_ERNAM;
    public String RES_Z_RBEAR;
    public String RES_Z_DBEAR;
    public String RES_Z_TBEAR;

    public List<CustomField> RES_CustomFields;
    public List<PlanInstallment> RES_Plan_Installments;
    public List<PaymentPlanAssignment> RES_Payment_Plan_Assignments;

    public class CustomField {
        public String name;
        public String value;
    }

    public class PlanInstallment {
        public String Change_Indicator;
        public String RES_Product_External_ID;
        public Integer RES_Sequence;
        public String RES_Installment_Payment_Type;
        public String Name;
        public Decimal RES_Installment_Percentage;
        public Decimal RES_POC_Percentage;
        public Decimal RES_Installment_Amount;
        public Integer Condition_Months;
        public Integer Condition_Days;
    }

    public class PaymentPlanAssignment {
        public String Change_Indicator;
        public String RES_Product_External_ID;
        public String RES_Business_Entity;
        public String RES_Construction_Phase;
        public String RES_Project;
        public String RES_UnitId;
        public String Company_Code;
    }

    public static RES_PaymentPlanWrapper parse(String jsonBody) {
        return (RES_PaymentPlanWrapper) JSON.deserialize(jsonBody, RES_PaymentPlanWrapper.class);
    }
}
