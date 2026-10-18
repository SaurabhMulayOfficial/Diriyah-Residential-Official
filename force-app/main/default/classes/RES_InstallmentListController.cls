/**
 * @description Backs resPaymentPlanInstallmentList: returns every Installment product under a Payment Plan bundle,
 * ordered by sequence, so the Payment Plan record page can show them in one table.
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

    @AuraEnabled(cacheable=true)
    public static List<Installment> getInstallments(Id paymentPlanId) {
        List<Installment> installments = new List<Installment>();
        if (paymentPlanId == null) {
            return installments;
        }
        try {
            Map<String, String> conditionTypeLabels = picklistLabels(Product2.RES_Condition_Type__c);
            for (ProductRelatedComponent component : COMPONENT_DAO.getComponentsByParentProducts(new Set<Id>{ paymentPlanId })) {
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
                installments.add(row);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Could not load the payment plan installments: ' + e.getMessage());
        }
        return installments;
    }

    private static Map<String, String> picklistLabels(Schema.SObjectField field) {
        Map<String, String> labels = new Map<String, String>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            labels.put(entry.getValue(), entry.getLabel());
        }
        return labels;
    }
}
