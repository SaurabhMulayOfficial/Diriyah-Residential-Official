/**
 * @description Wrapper for Property/Business Entity integration request.
 *              Represents the SAP inbound/outbound JSON payload including
 *              measurements and dynamic custom fields.
 */
public class RES_ProductCatalogWrapper {

    public String RES_Company_Code;
    public String RES_Business_Entity_Id;
    public String Name;
    public String EffectiveStartDate;
    public String EffectiveEndDate;
    public String RES_Tenancy_Law;
    public String RES_Profit_Center;
    public String RES_BP_Role;
    public String RES_BP_Number;
    public String Change_Indicator;

    public List<MeasurementWrapper> RES_Measurements;
    public List<CustomFieldWrapper> RES_CustomFields;

    public class MeasurementWrapper {
        public String RES_Measurement_Type;
        public Decimal RES_Measurement_Amount;
        public String RES_Measurement_From;
        public String RES_Measurement_To;
        public String Measurement_Change_Indicator;
    }

    public class CustomFieldWrapper {

        public CustomFieldWrapper(String name, String value){
            this.name = name;
            this.value = value;
        }
        public String name;
        public String value;
    }
}