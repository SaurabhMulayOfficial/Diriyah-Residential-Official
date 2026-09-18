public class RES_ProductCategoryRequestWrapper {
    public String RES_Company_Code;
    public String RES_Business_Entity_Id;
    public String RES_Property_ID;
    public String Name;
    public Datetime RES_Valid_From_Date;
    public Datetime RES_Valid_To_Date;
    public String RES_Profit_Center;
    public String RES_Property_Type;
    public String Change_Indicator;

    public List<Measurement> RES_Measurements;
    
    public class Measurement {
        public String RES_Measurement_Type;
        public Decimal RES_Measurement_Amount;
        public Date RES_Measurement_From;
        public Date RES_Measurement_To;
        public String Measurement_Change_Indicator;
    }
}