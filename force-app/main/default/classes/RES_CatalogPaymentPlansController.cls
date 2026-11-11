/**
 * @description Backs resCatalogPaymentPlans: every Payment Plan under a Product Catalog, grouped by root plan with all its POC versions.
 */
public with sharing class RES_CatalogPaymentPlansController {

    private static final String PAYMENT_PLAN_RECORD_TYPE_DEV_NAME = 'RES_Residential_Payment_Plan';
    private static final String CIP_TYPE_INSTALLMENT = 'Installment';

    public class PlanVersion {
        @AuraEnabled public Id id;
        @AuraEnabled public Id rootId;
        @AuraEnabled public String name;
        @AuraEnabled public String externalId;
        @AuraEnabled public Decimal version;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String approvalStatus;
        @AuraEnabled public String priceOption;
        @AuraEnabled public Decimal numberOfYears;
        @AuraEnabled public Date validFrom;
        @AuraEnabled public Date validityEndDate;
        @AuraEnabled public Integer installmentCount = 0;
    }

    public class PlanFamily {
        @AuraEnabled public Id rootId;
        // Latest version first; the original (root) plan is last
        @AuraEnabled public List<PlanVersion> versions = new List<PlanVersion>();
    }

    @AuraEnabled(cacheable=true)
    public static List<PlanFamily> getPaymentPlans(Id catalogId) {
        List<PlanFamily> families = new List<PlanFamily>();
        if (catalogId == null) {
            return families;
        }
        try {
            List<Product2> plans = [
                SELECT Id, Name, RES_Product_External_ID__c, RES_Version__c, RES_Parent_Payment_Plan__c, IsActive, RES_Approval_Status__c,
                       RES_Price_Option__c, RES_No_of_Years__c, AvailabilityDate, RES_Validity_End_Date__c
                FROM Product2
                WHERE RES_Business_Entity__c = :catalogId AND RecordType.DeveloperName = :PAYMENT_PLAN_RECORD_TYPE_DEV_NAME
                WITH SYSTEM_MODE
                ORDER BY Name ASC, RES_Version__c DESC NULLS LAST
            ];
            Map<Id, Integer> installmentCounts = installmentCounts(new Map<Id, Product2>(plans).keySet());
            Map<String, String> approvalLabels = picklistLabels(Product2.RES_Approval_Status__c);

            Map<Id, PlanFamily> familyByRoot = new Map<Id, PlanFamily>();
            for (Product2 plan : plans) {
                PlanVersion row = new PlanVersion();
                row.id = plan.Id;
                row.rootId = plan.RES_Parent_Payment_Plan__c ?? plan.Id;
                row.name = plan.Name;
                row.externalId = plan.RES_Product_External_ID__c;
                row.version = plan.RES_Version__c;
                row.isActive = plan.IsActive;
                row.approvalStatus = approvalLabels.get(plan.RES_Approval_Status__c) ?? plan.RES_Approval_Status__c;
                row.priceOption = plan.RES_Price_Option__c;
                row.numberOfYears = plan.RES_No_of_Years__c;
                row.validFrom = plan.AvailabilityDate?.date();
                row.validityEndDate = plan.RES_Validity_End_Date__c;
                row.installmentCount = installmentCounts.get(plan.Id) ?? 0;
                if (!familyByRoot.containsKey(row.rootId)) {
                    PlanFamily family = new PlanFamily();
                    family.rootId = row.rootId;
                    familyByRoot.put(row.rootId, family);
                }
                familyByRoot.get(row.rootId).versions.add(row);
            }
            for (PlanFamily family : familyByRoot.values()) {
                family.versions = sortLatestFirst(family.versions);
                families.add(family);
            }
            return families;
        } catch (Exception e) {
            throw new AuraHandledException('Could not load the payment plans: ' + e.getMessage());
        }
    }

    // Versions are sorted by number descending; the root (no version) is the oldest
    private static List<PlanVersion> sortLatestFirst(List<PlanVersion> versions) {
        List<PlanVersion> sorted = new List<PlanVersion>();
        PlanVersion root;
        Map<Decimal, PlanVersion> byNumber = new Map<Decimal, PlanVersion>();
        for (PlanVersion v : versions) {
            if (v.version == null) {
                root = v;
            } else {
                byNumber.put(v.version, v);
            }
        }
        List<Decimal> numbers = new List<Decimal>(byNumber.keySet());
        numbers.sort();
        for (Integer i = numbers.size() - 1; i >= 0; i--) {
            sorted.add(byNumber.get(numbers[i]));
        }
        if (root != null) {
            sorted.add(root);
        }
        return sorted;
    }

    private static Map<Id, Integer> installmentCounts(Set<Id> planIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (planIds.isEmpty()) {
            return counts;
        }
        for (AggregateResult result : [
            SELECT ParentProductId parentId, COUNT(Id) total
            FROM ProductRelatedComponent
            WHERE ParentProductId IN :planIds AND ChildProduct.RES_CIP_Type__c = :CIP_TYPE_INSTALLMENT
            WITH SYSTEM_MODE
            GROUP BY ParentProductId
        ]) {
            counts.put((Id) result.get('parentId'), (Integer) result.get('total'));
        }
        return counts;
    }

    private static Map<String, String> picklistLabels(Schema.SObjectField field) {
        Map<String, String> labels = new Map<String, String>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            labels.put(entry.getValue(), entry.getLabel());
        }
        return labels;
    }
}
