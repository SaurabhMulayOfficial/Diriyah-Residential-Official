/**
 * @description Backs resPaymentPlanInstallmentList (installments of one Payment Plan) and resUnitPaymentPlans
 * (every Payment Plan under a Unit, each with its installments).
 */
public with sharing class RES_InstallmentListController {

    private static final RES_ProductRelatedComponentDAOLayer COMPONENT_DAO = new RES_ProductRelatedComponentDAOLayer();

    public class Installment {
        @AuraEnabled public Id componentId;
        @AuraEnabled public Id productId;
        @AuraEnabled public Decimal sequence;
        @AuraEnabled public String name;
        @AuraEnabled public String productCode;
        @AuraEnabled public String paymentType;
        @AuraEnabled public String conditionType;
        @AuraEnabled public Decimal conditionMonths;
        @AuraEnabled public Decimal conditionDays;
        @AuraEnabled public Decimal percentage;
        @AuraEnabled public Decimal pocPercentage;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String currencyIsoCode;
        @AuraEnabled public Boolean isActive;
    }

    public class PaymentPlan {
        @AuraEnabled public Id componentId;
        @AuraEnabled public Id productId;
        @AuraEnabled public String name;
        @AuraEnabled public String productCode;
        @AuraEnabled public Decimal version;
        @AuraEnabled public Decimal numberOfYears;
        @AuraEnabled public Decimal numberOfMonths;
        @AuraEnabled public Date validityEndDate;
        @AuraEnabled public String approvalStatus;
        @AuraEnabled public String priceOption;
        @AuraEnabled public Boolean isDefault;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Decimal totalPercentage = 0;
        @AuraEnabled public List<Installment> installments = new List<Installment>();
    }

    @AuraEnabled(cacheable=true)
    public static List<Installment> getInstallments(Id paymentPlanId) {
        if (paymentPlanId == null) {
            return new List<Installment>();
        }
        try {
            List<Installment> installments = installmentsByPlanId(new Set<Id>{ paymentPlanId }).get(paymentPlanId);
            return installments ?? new List<Installment>();
        } catch (Exception e) {
            throw new AuraHandledException('Could not load the payment plan installments: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<PaymentPlan> getPaymentPlans(Id unitId) {
        List<PaymentPlan> plans = new List<PaymentPlan>();
        if (unitId == null) {
            return plans;
        }
        try {
            List<ProductRelatedComponent> planComponents = COMPONENT_DAO.getPaymentPlansByUnit(unitId);
            Set<Id> planIds = new Set<Id>();
            for (ProductRelatedComponent component : planComponents) {
                planIds.add(component.ChildProductId);
            }
            Map<Id, List<Installment>> installmentsByPlan = installmentsByPlanId(planIds);
            Map<String, String> approvalStatusLabels = picklistLabels(Product2.RES_Approval_Status__c);
            for (ProductRelatedComponent component : planComponents) {
                Product2 child = component.ChildProduct;
                PaymentPlan plan = new PaymentPlan();
                plan.componentId = component.Id;
                plan.productId = component.ChildProductId;
                plan.name = child.Name;
                plan.productCode = child.ProductCode;
                plan.version = child.RES_Version__c;
                plan.numberOfYears = child.RES_No_of_Years__c;
                plan.numberOfMonths = child.RES_No_of_Months__c;
                plan.validityEndDate = child.RES_Validity_End_Date__c;
                plan.approvalStatus = approvalStatusLabels.get(child.RES_Approval_Status__c) ?? child.RES_Approval_Status__c;
                plan.priceOption = component.RES_Price_Option__c;
                plan.isDefault = component.IsDefaultComponent;
                plan.isActive = child.IsActive;
                plan.installments = installmentsByPlan.get(plan.productId) ?? new List<Installment>();
                for (Installment row : plan.installments) {
                    plan.totalPercentage += row.percentage ?? 0;
                }
                plans.add(plan);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Could not load the payment plans: ' + e.getMessage());
        }
        return plans;
    }

    private static Map<Id, List<Installment>> installmentsByPlanId(Set<Id> planIds) {
        Map<Id, List<Installment>> result = new Map<Id, List<Installment>>();
        Map<String, String> conditionTypeLabels = picklistLabels(Product2.RES_Condition_Type__c);
        for (ProductRelatedComponent component : COMPONENT_DAO.getComponentsByParentProducts(planIds)) {
            Product2 child = component.ChildProduct;
            Installment row = new Installment();
            row.componentId = component.Id;
            row.productId = component.ChildProductId;
            row.sequence = child.RES_Sequence__c;
            row.name = child.Name;
            row.productCode = child.ProductCode;
            row.paymentType = child.RES_Installment_Payment_Type__c;
            row.conditionType = conditionTypeLabels.get(child.RES_Condition_Type__c) ?? child.RES_Condition_Type__c;
            row.conditionMonths = child.RES_Condition_Months__c;
            row.conditionDays = child.RES_Condition_Days__c;
            // The plan-level split on the component overrides the installment's own percentage
            row.percentage = component.RES_Installment_Percentage__c ?? child.RES_Installment_Percentage__c;
            row.pocPercentage = child.RES_POC_Percentage__c;
            row.dueDate = child.RES_Instalment_DueDate__c;
            row.amount = child.RES_Installment_Amount__c;
            row.currencyIsoCode = child.CurrencyIsoCode;
            row.isActive = child.IsActive;
            if (!result.containsKey(component.ParentProductId)) {
                result.put(component.ParentProductId, new List<Installment>());
            }
            result.get(component.ParentProductId).add(row);
        }
        return result;
    }

    private static Map<String, String> picklistLabels(Schema.SObjectField field) {
        Map<String, String> labels = new Map<String, String>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            labels.put(entry.getValue(), entry.getLabel());
        }
        return labels;
    }
}
