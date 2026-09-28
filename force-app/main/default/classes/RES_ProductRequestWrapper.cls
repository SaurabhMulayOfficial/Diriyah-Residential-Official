public class RES_ProductRequestWrapper {
    public String Family;
    public String RES_Business_Entity;
    public String RES_Building;
    public Datetime AvailabilityDate;
    public Datetime DiscontinuedDate;
    public String RES_Floor;
    public String RES_Profit_Center;
    public String RES_Unit_Status;
    public String Description;
    public String Change_Indicator;

    public List<Measurement> RES_Measurements;
    public List<Condition> RES_Conditions;
    public List<FixtureFitting> RES_Fixtures_Fittings;
    public List<CustomField> RES_CustomFields;
    public class Measurement {
        public String Name;
        public String RES_Measurement_Type;
        public Decimal RES_Measurement_Amount;
        public Date RES_Measurement_From;
        public Date RES_Measurement_To;
        public String RES_Unit_Of_Measurement;
        public String Change_Indicator;
    }

    public class Condition {
        public String RES_Condition_Type;
        public Decimal RES_Condition_Price;
        public String RES_Formula;
        public String RES_Parameter_1;
        public String RES_Parameter_2;
        public String RES_Calculation_Rule;
        public Decimal RES_Percentage;
        public String RES_Conditions_Purpose;
        public Date RES_Condition_Valid_From;
        public Date RES_Condition_Valid_To;
        public String Change_Indicator;
    }

    public class FixtureFitting {
        public String RES_Fixtures_Fittings_Characteristics;
        public String Change_Indicator;
    }

    public class CustomField {
        public String name;
        public String value;
    }
}
