/**
 * @description Backs resPaymentPlanPreview: reads the live configurator context to find the selected Payment Plan
 * under the unit being configured and returns its installments (percentage, due date, amount).
 */
public with sharing class RES_PaymentPlanPreviewController {

    private static final String DELETED = 'DELETED';
    private static final String PATH_SEPARATOR = '/';
    private static final String AMOUNT_TAG = 'RESInstallmentAmount__c';
    private static final String PERCENTAGE_TAG = 'RESInstallmentPercentage__c';

    private static final RES_ProductRelatedComponentDAOLayer COMPONENT_DAO = new RES_ProductRelatedComponentDAOLayer();

    @TestVisible
    private static RES_IndustriesContextProvider contextProvider;

    public class Preview {
        @AuraEnabled public String planName;
        @AuraEnabled public String currencyIsoCode;
        @AuraEnabled public Decimal totalPercentage = 0;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Boolean isPriced = false;
        @AuraEnabled public List<Installment> installments = new List<Installment>();
    }

    public class Installment {
        @AuraEnabled public Id productId;
        @AuraEnabled public Decimal sequence;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal percentage;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Decimal amount;
    }

    private class LineItem {
        String lineItemId;
        String parentLineItemId;
        String rootLineItemId;
        Id productId;
        Decimal installmentAmount;
        Decimal installmentPercentage;
    }

    /** Returns null when no Payment Plan is selected under the configured unit. */
    @AuraEnabled
    public static Preview getPreview(String contextId, String rootProductId) {
        if (String.isBlank(contextId)) {
            return null;
        }
        try {
            return buildPreview(readLineItems(contextId), rootProductId);
        } catch (Exception e) {
            throw new AuraHandledException('Could not load the payment plan installments: ' + e.getMessage());
        }
    }

    private static Preview buildPreview(List<LineItem> lines, String rootProductId) {
        List<LineItem> unitLines = linesUnderRoot(lines, rootProductId);
        Set<Id> candidateProductIds = new Set<Id>();
        for (LineItem line : unitLines) {
            if (line.productId != null) {
                candidateProductIds.add(line.productId);
            }
        }

        // Only a Payment Plan has Installment components, so the parents returned identify the selected plan
        Map<Id, List<ProductRelatedComponent>> installmentsByPlanId = new Map<Id, List<ProductRelatedComponent>>();
        for (ProductRelatedComponent component : COMPONENT_DAO.getComponentsByParentProducts(candidateProductIds)) {
            if (!installmentsByPlanId.containsKey(component.ParentProductId)) {
                installmentsByPlanId.put(component.ParentProductId, new List<ProductRelatedComponent>());
            }
            installmentsByPlanId.get(component.ParentProductId).add(component);
        }

        LineItem planLine;
        for (LineItem line : unitLines) {
            if (installmentsByPlanId.containsKey(line.productId)) {
                planLine = line;
                break;
            }
        }
        if (planLine == null) {
            return null;
        }

        Map<Id, LineItem> installmentLineByProductId = new Map<Id, LineItem>();
        for (LineItem line : unitLines) {
            if (line.parentLineItemId == planLine.lineItemId && line.productId != null) {
                installmentLineByProductId.put(line.productId, line);
            }
        }

        Product2 plan = RES_InstallmentDueDateService.planWithPhase(planLine.productId);
        String developmentPhase = plan?.RES_Business_Entity__r?.RES_Development_Phase__c;
        Date validFrom = plan?.AvailabilityDate?.date();
        Preview preview = new Preview();
        preview.planName = plan?.Name;
        Date today = Date.today();
        Decimal totalAmount = 0;
        for (ProductRelatedComponent component : installmentsByPlanId.get(planLine.productId)) {
            Product2 child = component.ChildProduct;
            LineItem line = installmentLineByProductId.get(component.ChildProductId);

            Installment row = new Installment();
            row.productId = component.ChildProductId;
            row.sequence = child.RES_Sequence__c;
            row.name = child.Name;
            row.percentage = firstNonNull(line?.installmentPercentage, component.RES_Installment_Percentage__c, child.RES_Installment_Percentage__c);
            row.dueDate = RES_InstallmentDueDateService.dueDateOnConfiguration(child, developmentPhase, today, validFrom);
            row.amount = line?.installmentAmount;
            preview.installments.add(row);

            preview.currencyIsoCode = preview.currencyIsoCode ?? child.CurrencyIsoCode;
            preview.totalPercentage += row.percentage ?? 0;
            if (row.amount != null) {
                preview.isPriced = true;
                totalAmount += row.amount;
            }
        }
        preview.totalAmount = preview.isPriced ? totalAmount : null;
        return preview;
    }

    /** Lines belonging to the configured unit; every line when the unit's own line cannot be found. */
    private static List<LineItem> linesUnderRoot(List<LineItem> lines, String rootProductId) {
        String rootLineItemId;
        for (LineItem line : lines) {
            if (line.parentLineItemId == null && rootProductId != null && String.valueOf(line.productId) == rootProductId) {
                rootLineItemId = line.lineItemId;
                break;
            }
        }
        if (rootLineItemId == null) {
            return lines;
        }
        List<LineItem> scoped = new List<LineItem>();
        for (LineItem line : lines) {
            if (line.rootLineItemId == rootLineItemId) {
                scoped.add(line);
            }
        }
        return scoped;
    }

    private static List<LineItem> readLineItems(String contextId) {
        RES_IndustriesContextProvider ctx = contextProvider ?? new RES_LiveIndustriesContextProvider();
        Map<String, Object> output = ctx.queryTags(new Map<String, Object>{
            'contextId' => contextId,
            'tags' => new List<String>{ 'SalesTransactionItem' }
        });
        Map<String, Object> queryResult = output == null ? null : (Map<String, Object>) output.get('queryResult');
        List<Object> nodes = queryResult == null ? null : (List<Object>) queryResult.get('SalesTransactionItem');

        List<LineItem> lines = new List<LineItem>();
        if (nodes == null) {
            return lines;
        }
        for (Object node : nodes) {
            Map<String, Object> tags = (Map<String, Object>) ((Map<String, Object>) node).get('tagValue');
            if (tags == null || isDeleted(tags)) {
                continue;
            }
            String lineItemId = stringTag(tags, 'LineItem');
            String path = stringTag(tags, 'LineItemPath');
            if (lineItemId == null) {
                continue;
            }
            List<String> segments = String.isBlank(path) ? new List<String>{ lineItemId } : path.split(PATH_SEPARATOR);

            LineItem line = new LineItem();
            line.lineItemId = lineItemId;
            line.rootLineItemId = segments[0];
            line.parentLineItemId = segments.size() > 1 ? segments[segments.size() - 2] : null;
            line.productId = toId(stringTag(tags, 'Product'));
            line.installmentAmount = decimalTag(tags, AMOUNT_TAG);
            line.installmentPercentage = decimalTag(tags, PERCENTAGE_TAG);
            lines.add(line);
        }
        return lines;
    }

    private static Boolean isDeleted(Map<String, Object> tags) {
        for (String tagName : new List<String>{ 'LineItemPath', 'LineItem' }) {
            Map<String, Object> tag = (Map<String, Object>) tags.get(tagName);
            if (tag != null && tag.get('dmlStatus') != null) {
                return DELETED.equals(String.valueOf(tag.get('dmlStatus')));
            }
        }
        return false;
    }

    private static Object rawTag(Map<String, Object> tags, String tagName) {
        Map<String, Object> tag = (Map<String, Object>) tags.get(tagName);
        return tag == null ? null : tag.get('tagValue');
    }

    private static String stringTag(Map<String, Object> tags, String tagName) {
        Object value = rawTag(tags, tagName);
        return value == null ? null : String.valueOf(value);
    }

    private static Decimal decimalTag(Map<String, Object> tags, String tagName) {
        String value = stringTag(tags, tagName);
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Decimal.valueOf(value);
        } catch (TypeException e) {
            return null;
        }
    }

    private static Id toId(String value) {
        try {
            return String.isBlank(value) ? null : Id.valueOf(value);
        } catch (StringException e) {
            return null;
        }
    }

    private static Decimal firstNonNull(Decimal first, Decimal second, Decimal third) {
        return first ?? second ?? third;
    }
}
