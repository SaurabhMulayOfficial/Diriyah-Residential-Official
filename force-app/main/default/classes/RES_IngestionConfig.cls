/**
 * Reads and caches the ingestion configuration held in custom metadata via DAO layer.
 */
public with sharing class RES_IngestionConfig {

    private static List<Layout> cachedLayouts;
    private static Map<String, List<ColumnMap>> columnMapsByLayout = new Map<String, List<ColumnMap>>();
    private static Map<String, List<TargetMap>> targetMapsByLayout = new Map<String, List<TargetMap>>();

    public class Layout {
        @AuraEnabled public String code;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public String keyColumn;
        public String productRecordType;
        public String expectedInventoryType;
        public String inventoryTypeField;
        public String pricebookName;
        public String productClassification;
        public String selectorAttribute;
        public String priceAdjustmentSchedule;
        public String attributeCategory;
        public Integer displayOrder;
    }

    public class ColumnMap {
        public String sourceHeader;
        public Integer occurrence;
        public String stagingField;
        public String dateFormat;
        public Boolean stripSeparators;
        public Boolean isRequired;
        public String defaultValue;
    }

    public class TargetMap {
        public String stagingField;
        public String targetObject;
        public String targetField;
        public String valueKind;
        public String literalValue;
        public String mergeStrategy;
        public Boolean skipOnUpdate;
        public String measurementType;
        public String unitOfMeasurement;
        public String attributeName;
        public String sourceCode;
    }

    public class ConditionMapping {
        public String conditionType;
        public String handling;
        public String attributeName;
        public String attributeDataType;
        public String sellingModelType;
        public Integer pricingTerm;
        public String pricingTermUnit;
        public Boolean isPrimary;
        public String selectorValue;
        public String adjustmentType;
    }

    // Layouts

    public static List<Layout> activeLayouts() {
        if (cachedLayouts != null) return cachedLayouts;

        cachedLayouts = new List<Layout>();
        List<RES_Ingestion_Layout__mdt> layouts = new RES_IngestionLayoutDAOLayer().getActiveLayouts();
        
        for (RES_Ingestion_Layout__mdt m : layouts) {
            Layout l               = new Layout();
            l.code                 = m.RES_Layout_Code__c;
            l.label                = m.Label;
            l.description          = m.RES_Description__c;
            l.keyColumn            = m.RES_Key_Column__c;
            l.productRecordType    = m.RES_Product_Record_Type__c;
            l.expectedInventoryType = m.RES_Expected_Inventory_Type__c;
            l.inventoryTypeField    = m.RES_Inventory_Type_Column__c;
            l.pricebookName         = m.RES_Pricebook_Name__c;
            l.productClassification    = m.RES_Product_Classification__c;
            l.selectorAttribute        = m.RES_Selector_Attribute__c;
            l.priceAdjustmentSchedule  = m.RES_Price_Adjustment_Schedule__c;
            l.attributeCategory        = m.RES_Attribute_Category__c;
            l.displayOrder     = m.RES_Display_Order__c == null ? null : Integer.valueOf(m.RES_Display_Order__c);
            cachedLayouts.add(l);
        }
        return cachedLayouts;
    }

    public static Layout layoutByCode(String code) {
        if (String.isBlank(code)) return null;
        for (Layout l : activeLayouts()) {
            if (l.code.equalsIgnoreCase(code)) return l;
        }
        return null;
    }

    // Column maps (CSV -> staging)

    public static List<ColumnMap> columnMaps(String layoutCode) {
        if (String.isBlank(layoutCode)) return new List<ColumnMap>();
        if (columnMapsByLayout.containsKey(layoutCode)) return columnMapsByLayout.get(layoutCode);

        List<ColumnMap> maps = new List<ColumnMap>();
        List<RES_Csv_Column_Map__mdt> records = new RES_CsvColumnMapDAOLayer().getActiveColumnMapsByLayoutCode(layoutCode);
        
        for (RES_Csv_Column_Map__mdt m : records) {
            ColumnMap c        = new ColumnMap();
            c.sourceHeader     = m.RES_Source_Header__c;
            c.occurrence       = m.RES_Header_Occurrence__c == null
                                 ? 0 : Integer.valueOf(m.RES_Header_Occurrence__c);
            c.stagingField     = m.RES_Staging_Field__c;
            c.dateFormat       = m.RES_Date_Format__c;
            c.stripSeparators  = m.RES_Strip_Thousand_Separators__c == true;
            c.isRequired       = m.RES_Is_Required__c == true;
            c.defaultValue     = m.RES_Default_Value__c;
            maps.add(c);
        }
        columnMapsByLayout.put(layoutCode, maps);
        return maps;
    }

    // Target maps (staging -> Revenue Cloud)

    public static List<TargetMap> targetMaps(String layoutCode) {
        if (String.isBlank(layoutCode)) return new List<TargetMap>();
        if (targetMapsByLayout.containsKey(layoutCode)) return targetMapsByLayout.get(layoutCode);

        List<TargetMap> maps = new List<TargetMap>();
        List<RES_Target_Field_Map__mdt> records = new RES_TargetFieldMapDAOLayer().getActiveTargetMapsByLayoutCode(layoutCode);
        
        for (RES_Target_Field_Map__mdt m : records) {
            TargetMap t          = new TargetMap();
            t.stagingField       = m.RES_Staging_Field__c;
            t.targetObject       = m.RES_Target_Object__c;
            t.targetField        = m.RES_Target_Field__c;
            t.valueKind          = String.isBlank(m.RES_Value_Kind__c) ? 'Direct' : m.RES_Value_Kind__c;
            t.literalValue       = m.RES_Literal_Value__c;
            t.mergeStrategy      = String.isBlank(m.RES_Merge_Strategy__c) ? 'First_Non_Null' : m.RES_Merge_Strategy__c;
            t.skipOnUpdate       = m.RES_Skip_On_Update__c == true;
            t.measurementType    = m.RES_Measurement_Type__c;
            t.unitOfMeasurement  = m.RES_Unit_Of_Measurement__c;
            t.attributeName      = m.RES_Attribute_Name__c;
            t.sourceCode         = m.RES_Source_Code__c;
            maps.add(t);
        }
        targetMapsByLayout.put(layoutCode, maps);
        return maps;
    }

    public static List<TargetMap> targetMapsFor(String layoutCode, String targetObject) {
        List<TargetMap> subset = new List<TargetMap>();
        for (TargetMap t : targetMaps(layoutCode)) {
            if (targetObject.equalsIgnoreCase(t.targetObject)) subset.add(t);
        }
        return subset;
    }

    // Condition mappings

    private static Map<String, Map<String, ConditionMapping>> conditionsByLayout =
        new Map<String, Map<String, ConditionMapping>>();

    public static Map<String, ConditionMapping> conditionMappings(String layoutCode) {
        if (String.isBlank(layoutCode)) return new Map<String, ConditionMapping>();
        if (conditionsByLayout.containsKey(layoutCode)) return conditionsByLayout.get(layoutCode);

        Map<String, ConditionMapping> byCode = new Map<String, ConditionMapping>();
        List<RES_Condition_Mapping__mdt> records = new RES_ConditionMappingDAOLayer().getActiveConditionMappingsByLayoutCode(layoutCode);

        for (RES_Condition_Mapping__mdt m : records) {
            if (String.isBlank(m.RES_Condition_Type__c)) continue;
            ConditionMapping c   = new ConditionMapping();
            c.conditionType      = m.RES_Condition_Type__c.trim().toUpperCase();
            c.handling           = String.isBlank(m.RES_Handling__c) ? 'Pricebook_Entry' : m.RES_Handling__c;
            c.attributeName      = m.RES_Attribute_Name__c;
            c.attributeDataType  = String.isBlank(m.RES_Attribute_Data_Type__c) ? 'Currency' : m.RES_Attribute_Data_Type__c;
            c.sellingModelType   = String.isBlank(m.RES_Selling_Model_Type__c) ? 'OneTime' : m.RES_Selling_Model_Type__c;
            c.pricingTerm        = m.RES_Pricing_Term__c == null ? null : Integer.valueOf(m.RES_Pricing_Term__c);
            c.pricingTermUnit    = m.RES_Pricing_Term_Unit__c;
            c.isPrimary          = m.RES_Is_Primary__c == true;
            c.selectorValue      = m.RES_Selector_Value__c;
            c.adjustmentType     = String.isBlank(m.RES_Adjustment_Type__c) ? 'Override' : m.RES_Adjustment_Type__c;
            byCode.put(c.conditionType, c);
        }
        conditionsByLayout.put(layoutCode, byCode);
        return byCode;
    }

    public static ConditionMapping conditionMapping(String layoutCode, String conditionType) {
        if (String.isBlank(conditionType)) return null;
        return conditionMappings(layoutCode).get(conditionType.trim().toUpperCase());
    }

    @TestVisible
    private static List<String> splitList(String raw) {
        List<String> out = new List<String>();
        if (String.isBlank(raw)) return out;
        for (String part : raw.split(';')) {
            if (String.isNotBlank(part)) out.add(part.trim());
        }
        return out;
    }
}