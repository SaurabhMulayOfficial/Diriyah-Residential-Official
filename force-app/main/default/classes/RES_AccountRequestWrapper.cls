/**
 * @description Data Transfer Object for SAP S/4HANA Business Partner / Account Payload.
 * @CreatedDate : 23/09/2026
 * @LastModifiedDate : 23/09/2026
 * @Author : Nitin Marathe
 */
public class RES_AccountRequestWrapper {
    public String Id;
    public String RecordTypeId;
    public String Type;
    public String PersonTitle;
    public String LastName;
    public String Name;
    public String RES_Language;
    public String Phone;
    public String PersonGenderIdentity;
    public String RES_Marital_Status;
    public String RES_Nationality;
    public String RES_Date_of_Birth;
    public String RES_Company_Additional_Name;
    public String RES_OBJECT_TASK;
    public String RES_BP_NUMBER;
    public String RES_NAME1;
    public String RES_NAME2;
    public String RES_KTOKD;
    public TaxNumbers TT_TAX_NUMBERS;
    public String RES_Relationship_Type;
    public String Change_Indicator;
    public String Fullname;
    public String Account_Category;
    public Addresses TT_ADDRESSES;
    public Roles TT_ROLES;
    public List<CompanyCodeWrapper> RES_Company_Codes;
    public Identifications TT_IDENTIFICATIONS;
    public CompanyCodes TT_COMPANY_CODES;
    public List<CustomField> RES_CustomFields;
    public String CONTACT_PERSON_TASK;
    public String CONTACT_PERSON_BP;
    public String HAS_CONTACT_PERSON;
    public String CONTACT_PERSON_GROUPING;
    public String CONTACT_PERSON_TITLE;
    public String CONTACT_PERSON_END_DATE;

    public class TaxNumbers {
        public TaxItem item;
    }

    public class TaxItem {
        public String OBJECT_TASK;
        public String TAXTYPE;
        public String TAXNUMBER;
    }

    public class Addresses {
        public AddressItem item;
    }

    public class AddressItem {
        public String OBJECT_TASK;
        public String ADDRNUMBER;
        public String CITY;
        public String POSTL_COD1;
        public String STREET;
        public String COUNTRY;
        public String LANGU;
        public Phones TT_PHONES;
        public Faxes TT_FAXES;
        public Emails TT_EMAILS;
    }

    public class Phones {
        public PhoneItem item;
    }

    public class PhoneItem {
        public String OBJECT_TASK;
        public String TELEPHONE;
        public String EXTENSION;
        public String COUNTRY;
    }

    public class Faxes {
        public FaxItem item;
    }

    public class FaxItem {
        public String OBJECT_TASK;
        public String FAX;
        public String COUNTRY;
    }

    public class Emails {
        public EmailItem item;
    }

    public class EmailItem {
        public String OBJECT_TASK;
        public String E_MAIL;
    }

    public class Roles {
        public List<RoleItem> item;
    }

    public class RoleItem {
        public String OBJECT_TASK;
        public String DATA_KEY;
    }

    public class CompanyCodeWrapper {
        public String RES_Company_Code;
        public String RES_Reconciliation_Account;
        public String RES_Planning_Group;
        public String Company_Code_Change_Indicator;
    }

    public class Identifications {
        public IdentificationItem item;
    }

    public class IdentificationItem {
        public String OBJECT_TASK;
        public String IDENTIFICATIONCATEGORY;
        public String IDENTIFICATIONNUMBER;
        public String IDENTRYDATE;
        public String IDVALIDFROMDATE;
        public String IDVALIDTODATE;
    }

    public class CompanyCodes {
        public List<CompanyCodeItem> item;
    }

    public class CompanyCodeItem {
        public String OBJECT_TASK;
        public String BUKRS;
        public String AKONT;
    }

    public class CustomField {
        public String name;
        public Object value;

        public CustomField(String name, Object value) {
            this.name = name;
            this.value = value;
        }
    }
}