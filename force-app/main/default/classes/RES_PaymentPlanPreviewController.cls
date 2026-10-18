/**
 * @description Backs resPaymentPlanPreview: given the products currently selected in the configurator, finds the
 * Payment Plan among them and returns its installments (percentage, due date, amount).
 */
public with sharing class RES_PaymentPlanPreviewController {

    private static final RES_ProductRelatedComponentDAOLayer COMPONENT_DAO = new RES_ProductRelatedComponentDAOLayer();

    public class Preview {
        @AuraEnabled public Id planProductId;
        @AuraEnabled public String planName;
        @AuraEnabled public String currencyIsoCode;
        @AuraEnabled public Decimal totalPercentage = 0;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public List<Installment> installments = new List<Installment>();
    }

    public class Installment {
        @AuraEnabled public Id productId;
        @AuraEnabled public Decimal sequence;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal percentage;
        @AuraEnabled public Decimal pocPercentage;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Decimal amount;
    }

    /** Returns null when none of the selected products is a Payment Plan. */
    @AuraEnabled
    public static Preview getPreview(List<String> selectedProductIds, String rootProductId) {
        try {
            return buildPreview(toIds(selectedProductIds), toId(rootProductId));
        } catch (Exception e) {
            throw new AuraHandledException('Could not load the payment plan installments: ' + e.getMessage());
        }
    }

    private static Preview buildPreview(List<Id> selectedProductIds, Id unitProductId) {
        if (selectedProductIds.isEmpty()) {
            return null;
        }

        // Only a Payment Plan has Installment components, so the parents returned identify the selected plan
        Map<Id, List<ProductRelatedComponent>> installmentsByPlanId = new Map<Id, List<ProductRelatedComponent>>();
        for (ProductRelatedComponent component : COMPONENT_DAO.getComponentsByParentProducts(new Set<Id>(selectedProductIds))) {
            if (!installmentsByPlanId.containsKey(component.ParentProductId)) {
                installmentsByPlanId.put(component.ParentProductId, new List<ProductRelatedComponent>());
            }
            installmentsByPlanId.get(component.ParentProductId).add(component);
        }

        Id planProductId;
        for (Id productId : selectedProductIds) {
            if (installmentsByPlanId.containsKey(productId)) {
                planProductId = productId;
                break;
            }
        }
        if (planProductId == null) {
            return null;
        }

        Product2 plan = RES_InstallmentDueDateService.planWithPhase(planProductId);
        String developmentPhase = plan?.RES_Business_Entity__r?.RES_Development_Phase__c;
        Date validFrom = plan?.AvailabilityDate?.date();
        Decimal amountBase = RES_ResidentialBundlePricingHook.planAdjustmentValue(unitProductId, planProductId);

        Preview preview = new Preview();
        preview.planProductId = planProductId;
        preview.planName = plan?.Name;
        Date today = Date.today();
        for (ProductRelatedComponent component : installmentsByPlanId.get(planProductId)) {
            Product2 child = component.ChildProduct;

            Installment row = new Installment();
            row.productId = component.ChildProductId;
            row.sequence = child.RES_Sequence__c;
            row.name = child.Name;
            row.percentage = component.RES_Installment_Percentage__c ?? child.RES_Installment_Percentage__c;
            row.pocPercentage = child.RES_POC_Percentage__c;
            row.dueDate = RES_InstallmentDueDateService.dueDateOnConfiguration(child, developmentPhase, today, validFrom);
            // Same rule as RES_ResidentialBundlePricingHook: adjustment value x installment percentage
            row.amount = (amountBase == null || row.percentage == null) ? null : amountBase * (row.percentage / 100);
            preview.installments.add(row);

            preview.currencyIsoCode = preview.currencyIsoCode ?? child.CurrencyIsoCode;
            preview.totalPercentage += row.percentage ?? 0;
            if (row.amount != null) {
                preview.totalAmount = (preview.totalAmount ?? 0) + row.amount;
            }
        }
        return preview;
    }

    private static List<Id> toIds(List<String> values) {
        List<Id> ids = new List<Id>();
        for (String value : values ?? new List<String>()) {
            Id parsed = toId(value);
            if (parsed != null) {
                ids.add(parsed);
            }
        }
        return ids;
    }

    private static Id toId(String value) {
        try {
            return String.isBlank(value) ? null : Id.valueOf(value);
        } catch (StringException e) {
            return null;
        }
    }
}
