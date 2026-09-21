/**
 * @description Pre-hook applying Pricing Option override, Payment Plan installment %, and Service Charge pricing to a bundle.
 * @author Sumit Dashora
 */
global class RES_ResidentialBundlePricingHook implements RevSignaling.SignalingApexProcessor {

    public virtual class BaseException extends Exception {}
    public class AdjustmentNotFoundException extends BaseException {}

    private static final String DEBUG_VERSION = 'V2.5_ServiceChargeViaFlattenedField';

    // ProductRelatedComponent field driving which adjustment applies (not Product2 - allows reuse across bundles)
    private static final String CHILD_PRICE_OPTION_SOURCE_FIELD = 'RES_Price_Option__c';

    // Installment's % share of its payment plan's price, on the option-to-installment relationship
    private static final String INSTALLMENT_PERCENTAGE_SOURCE_FIELD = 'RES_Installment_Percentage__c';

    // AttributeDefinition.DeveloperName the AttributeAdjustmentCondition records match against
    private static final String PRICE_OPTION_MATCHING_ATTRIBUTE = 'Pricing_Option';

    // Configurable per-org via Custom Label, since the rate attribute's DeveloperName is not
    // consistent across orgs (e.g. 'SC_RATE' in dev vs 'Service_Charge_Rate' in UAT) - hardcoding
    // it here would silently break service charge calculation in any org that names it differently.
    private static final String SERVICE_CHARGE_RATE_ATTRIBUTE = Label.RES_Service_Charge_Rate_Attribute;
    private static final String SERVICE_CHARGE_COMPONENT_NAME = 'Service Charge';
    private static final String SERVICE_CHARGE_AMOUNT_FIELD = 'RES_Service_Charge_Amount__c';

    // Additional line item attributes usable for finer (AND) matching, keyed by DeveloperName
    private static final Set<String> MATCHING_ATTRIBUTES = new Set<String>{
        PRICE_OPTION_MATCHING_ATTRIBUTE
    };

    // Supported AttributeAdjustmentCondition.Operator values for text-attribute matching
    private static final String OPERATOR_EQUALS = 'equals';
    private static final String OPERATOR_NOT_EQUALS = 'notequals';

    /** execute() stays a thin wrapper - RevSignaling.TransactionRequest has no accessible constructor, so all logic lives in executeInternal for testability. */
    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        return executeInternal(request.ctxInstanceId, new RES_LiveIndustriesContextProvider());
    }

    @TestVisible
    private RevSignaling.TransactionResponse executeInternal(String contextId, RES_IndustriesContextProvider industriesContext) {
        System.debug(DEBUG_VERSION + ' - Executing Pre-Hook: Bundle Pricing Option Adjustment');

        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();

        try {
            // STEP 1: Query SalesTransactionItem to identify bundle hierarchy
            Map<String, BundleStructure> bundleStructureMap = queryBundleStructure(industriesContext, contextId);
            System.debug(DEBUG_VERSION + ' - Identified ' + bundleStructureMap.size() + ' bundle structures');

            // STEP 2: Query item attributes and each existing dynamic attribute's node path
            Map<String, List<Object>> attributeNodePathMap = new Map<String, List<Object>>();
            Map<String, Map<String, String>> itemAttributeMap = queryItemAttributes(industriesContext, contextId, attributeNodePathMap);
            System.debug(DEBUG_VERSION + ' - Queried attributes for ' + itemAttributeMap.size() + ' items');

            // STEP 3: Query attribute-based adjustments for bundle products
            Map<String, List<AttributeAdjustment>> bundleAdjustmentsMap = queryAttributeAdjustments(bundleStructureMap);
            System.debug(DEBUG_VERSION + ' - Loaded adjustments for ' + bundleAdjustmentsMap.size() + ' bundle products');

            // STEP 4: Query RES_Price_Option__c from each selected option's ProductRelatedComponent
            Map<String, String> relatedComponentPriceOptionMap = queryChildOptionPriceValues(bundleStructureMap);
            System.debug(DEBUG_VERSION + ' - Loaded ' + CHILD_PRICE_OPTION_SOURCE_FIELD + ' for ' +
                       relatedComponentPriceOptionMap.size() + ' bundle-to-option relationships');

            // STEP 4.5: Query each installment's percentage share of its payment plan's price
            Map<String, Decimal> installmentPercentageMap = queryInstallmentPercentages(bundleStructureMap);
            System.debug(DEBUG_VERSION + ' - Loaded ' + INSTALLMENT_PERCENTAGE_SOURCE_FIELD + ' for ' +
                       installmentPercentageMap.size() + ' option-to-installment relationships');

            // STEP 4.6: Query each bundle's Net Saleable Area for the service charge calc
            Map<Id, Decimal> netSaleableAreaMap = queryNetSaleableAreaByProduct(bundleStructureMap);
            System.debug(DEBUG_VERSION + ' - Loaded RES_Net_Saleable_Area__c for ' +
                       netSaleableAreaMap.size() + ' bundle product(s)');

            // STEP 4.7: Identify which child option is the 'Service Charge' component
            Set<Id> serviceChargeProductIds = queryServiceChargeProductIds(bundleStructureMap);
            System.debug(DEBUG_VERSION + ' - Identified ' + serviceChargeProductIds.size() + ' service charge product(s)');

            // STEP 4.8: Query each bundle's SC_RATE from catalog config (not the live context)
            Map<Id, Decimal> serviceChargeRateMap = queryServiceChargeRateByProduct(bundleStructureMap);
            System.debug(DEBUG_VERSION + ' - Loaded ' + SERVICE_CHARGE_RATE_ATTRIBUTE + ' for ' +
                       serviceChargeRateMap.size() + ' bundle product(s)');

            // STEP 5: Match and apply adjustments to the selected child options
            List<Map<String, Object>> allNodeUpdates = applyPricingToOptions(
                bundleStructureMap,
                itemAttributeMap,
                bundleAdjustmentsMap,
                relatedComponentPriceOptionMap,
                attributeNodePathMap,
                installmentPercentageMap,
                netSaleableAreaMap,
                serviceChargeProductIds,
                serviceChargeRateMap
            );

            // STEP 6: Submit context updates
            if (!allNodeUpdates.isEmpty()) {
                Map<String, Object> updateInput = new Map<String, Object>{
                    'contextId' => contextId,
                    'nodePathAndAttributes' => allNodeUpdates
                };
                System.debug(DEBUG_VERSION + ' - Submitting ' + allNodeUpdates.size() + ' pricing updates');
                System.debug(DEBUG_VERSION + ' - Update payload: ' + JSON.serializePretty(updateInput));

                Object updateResult = industriesContext.updateContextAttributes(updateInput);
                System.debug(DEBUG_VERSION + ' - updateContextAttributes result: ' + JSON.serializePretty(updateResult));

                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = DEBUG_VERSION + ': Applied ' + allNodeUpdates.size() + ' pricing adjustments driven by selected option components';
            } else {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = DEBUG_VERSION + ': No pricing adjustments needed';
                System.debug(DEBUG_VERSION + ' - No updates to apply');
            }

        } catch (Exception e) {
            System.debug(DEBUG_VERSION + ' - ERROR: ' + e.getMessage());
            System.debug(DEBUG_VERSION + ' - Stack Trace: ' + e.getStackTraceString());
            response.status = RevSignaling.TransactionStatus.FAILED;
            response.message = DEBUG_VERSION + ' Error: ' + e.getMessage();
        }

        return response;
    }

    /**
     * Query SalesTransactionItem to build bundle-to-options hierarchy
     */
    @TestVisible
    private Map<String, BundleStructure> queryBundleStructure(
        RES_IndustriesContextProvider ctx,
        String contextId
    ) {
        Map<String, Object> queryInput = new Map<String, Object>{
            'contextId' => contextId,
            'tags' => new List<String>{'SalesTransactionItem'}
        };

        Map<String, Object> queryOutput = ctx.queryTags(queryInput);
        Map<String, Object> queryResult = (Map<String, Object>) queryOutput.get('queryResult');
        List<Object> itemList = (List<Object>) queryResult.get('SalesTransactionItem');

        System.debug(DEBUG_VERSION + ' - SalesTransactionItem Query Result: ' + JSON.serializePretty(queryResult));

        Map<String, BundleStructure> bundleMap = new Map<String, BundleStructure>();

        if (itemList != null) {
            for (Object itemObj : itemList) {
                Map<String, Object> itemNode = (Map<String, Object>) itemObj;
                Map<String, Object> tagValue = (Map<String, Object>) itemNode.get('tagValue');
                List<Object> dataPath = (List<Object>) itemNode.get('dataPath');

                if (tagValue == null || !tagValue.containsKey('LineItem') || !tagValue.containsKey('LineItemPath')) {
                    continue;
                }

                // Check DML status - skip deleted items
                String dmlStatus = getDmlStatus(tagValue);
                if ('DELETED'.equals(dmlStatus)) {
                    System.debug(DEBUG_VERSION + ' - Skipping DELETED item');
                    continue;
                }

                String lineItemId = getTagValue(tagValue, 'LineItem');
                String lineItemPath = getTagValue(tagValue, 'LineItemPath');
                String productId = getTagValue(tagValue, 'Product');

                // Build node path for updates (QuoteId, LineContextId)
                List<Object> nodePath = new List<Object>();
                if (dataPath != null && dataPath.size() >= 3) {
                    nodePath.add(dataPath.get(1)); // QuoteId
                    nodePath.add(dataPath.get(2)); // LineContextId
                }

                // Determine parent-child relationship
                if (lineItemPath != null && lineItemPath.contains('/')) {
                    // This is a child option - lineItemPath format: "parentId/childId"
                    String parentBundleId = lineItemPath.split('/')[0];

                    if (!bundleMap.containsKey(parentBundleId)) {
                        bundleMap.put(parentBundleId, new BundleStructure(parentBundleId, null));
                    }

                    bundleMap.get(parentBundleId).addChildOption(
                        new OptionItem(lineItemId, productId, nodePath, lineItemPath)
                    );

                    System.debug(DEBUG_VERSION + ' - Added child option: ' + lineItemId + ' to bundle: ' + parentBundleId);
                } else {
                    // This is a parent bundle or standalone item
                    if (!bundleMap.containsKey(lineItemId)) {
                        bundleMap.put(lineItemId, new BundleStructure(lineItemId, productId));
                    } else {
                        bundleMap.get(lineItemId).productId = productId;
                    }
                    bundleMap.get(lineItemId).nodePath = nodePath;

                    System.debug(DEBUG_VERSION + ' - Identified bundle: ' + lineItemId + ', Product: ' + productId);
                }
            }
        }

        return bundleMap;
    }

    /** Query SalesTransactionItemAttribute; also records each matching attribute's node path (needed to update an existing dynamic attribute later - this hook can't create new ones). */
    @TestVisible
    private Map<String, Map<String, String>> queryItemAttributes(
        RES_IndustriesContextProvider ctx,
        String contextId,
        Map<String, List<Object>> attributeNodePathMap
    ) {
        Map<String, Object> queryInput = new Map<String, Object>{
            'contextId' => contextId,
            'tags' => new List<String>{'SalesTransactionItemAttribute'}
        };

        Map<String, Object> queryOutput = ctx.queryTags(queryInput);
        Map<String, Object> queryResult = (Map<String, Object>) queryOutput.get('queryResult');
        List<Object> attrList = (List<Object>) queryResult.get('SalesTransactionItemAttribute');

        System.debug(DEBUG_VERSION + ' - SalesTransactionItemAttribute Query Result: ' + JSON.serializePretty(queryResult));

        Map<String, Map<String, String>> attributeMap = new Map<String, Map<String, String>>();

        if (attrList != null) {
            for (Object attrObj : attrList) {
                Map<String, Object> attrNode = (Map<String, Object>) attrObj;
                Map<String, Object> tagValue = (Map<String, Object>) attrNode.get('tagValue');
                List<Object> attrDataPath = (List<Object>) attrNode.get('dataPath');

                String attributeName = getTagValue(tagValue, 'Attribute');
                String attributeValue = getTagValue(tagValue, 'AttributeValue');
                String parentItemId = getTagValue(tagValue, 'SalesTransactionItemAttrParent');

                if (parentItemId == null || attributeName == null) {
                    continue;
                }

                if (!attributeMap.containsKey(parentItemId)) {
                    attributeMap.put(parentItemId, new Map<String, String>());
                }

                if (MATCHING_ATTRIBUTES.contains(attributeName) && attributeValue != null) {
                    attributeMap.get(parentItemId).put(attributeName, attributeValue);
                    System.debug(DEBUG_VERSION + ' - Item: ' + parentItemId + ', Attribute: ' + attributeName + ' = ' + attributeValue);

                    // dataPath is [contextId, quoteId, parentLineRef, attributeNodeRef] - strip contextId for the relative path
                    if (attrDataPath != null && attrDataPath.size() >= 4 && attributeNodePathMap != null) {
                        List<Object> relativeAttrNodePath = new List<Object>{
                            attrDataPath[1], attrDataPath[2], attrDataPath[3]
                        };
                        attributeNodePathMap.put(parentItemId + ':' + attributeName, relativeAttrNodePath);
                        System.debug(DEBUG_VERSION + ' - Found existing attribute node for ' + parentItemId +
                                   ':' + attributeName + ' at path ' + relativeAttrNodePath);
                    }
                }
            }
        }

        return attributeMap;
    }

    /** Query attribute-based adjustments for bundle products, joining each rule's conditions in a second query. */
    @TestVisible
    private Map<String, List<AttributeAdjustment>> queryAttributeAdjustments(
        Map<String, BundleStructure> bundleMap
    ) {
        Map<String, List<AttributeAdjustment>> adjustmentMap = new Map<String, List<AttributeAdjustment>>();

        Set<Id> bundleProductIds = new Set<Id>();
        for (BundleStructure bundle : bundleMap.values()) {
            if (bundle.productId != null && bundle.productId instanceof Id) {
                bundleProductIds.add((Id)bundle.productId);
            }
        }

        if (bundleProductIds.isEmpty()) {
            System.debug(DEBUG_VERSION + ' - No valid bundle product IDs found');
            return adjustmentMap;
        }

        System.debug(DEBUG_VERSION + ' - Querying adjustments for ' + bundleProductIds.size() + ' bundle products');

        List<AttributeBasedAdjustment> adjustments = [
            SELECT Id, Name, ProductId, AdjustmentType, AdjustmentValue,
                   PriceAdjustmentScheduleId, AttributeBasedAdjRuleId
            FROM AttributeBasedAdjustment
            WHERE ProductId IN :bundleProductIds
        ];

        System.debug(DEBUG_VERSION + ' - Found ' + adjustments.size() + ' attribute-based adjustments');

        Set<Id> ruleIds = new Set<Id>();
        for (AttributeBasedAdjustment adj : adjustments) {
            if (adj.AttributeBasedAdjRuleId != null) {
                ruleIds.add(adj.AttributeBasedAdjRuleId);
            }
        }

        Map<Id, List<AttributeAdjustmentCondition>> conditionsByRuleId = new Map<Id, List<AttributeAdjustmentCondition>>();
        if (!ruleIds.isEmpty()) {
            for (AttributeBasedAdjRule rule : [
                SELECT Id,
                       (SELECT Id, AttributeDefinitionId, AttributeDefinition.DeveloperName,
                               Operator, StringValue, ProductId
                        FROM AttributeAdjustmentConditions)
                FROM AttributeBasedAdjRule
                WHERE Id IN :ruleIds
            ]) {
                conditionsByRuleId.put(rule.Id, rule.AttributeAdjustmentConditions);
            }
        }

        // Group adjustments by ProductId, attaching each adjustment's conditions from its rule
        for (AttributeBasedAdjustment adj : adjustments) {
            String productId = adj.ProductId;

            if (!adjustmentMap.containsKey(productId)) {
                adjustmentMap.put(productId, new List<AttributeAdjustment>());
            }

            List<AttributeAdjustmentCondition> conditions = conditionsByRuleId.get(adj.AttributeBasedAdjRuleId);

            AttributeAdjustment adjInfo = new AttributeAdjustment(
                adj.Id,
                adj.Name,
                adj.AdjustmentType,
                adj.AdjustmentValue,
                null,  // no standard per-option restriction field; use an AttributeAdjustmentCondition instead
                conditions
            );

            adjustmentMap.get(productId).add(adjInfo);

            System.debug(DEBUG_VERSION + ' - Adjustment loaded: ' + adj.Name +
                       ' -> ' + adj.AdjustmentType + ': ' + adj.AdjustmentValue +
                       ' with ' + (conditions != null ? conditions.size() : 0) + ' conditions');
        }

        return adjustmentMap;
    }

    /** Query RES_Price_Option__c from the ProductRelatedComponent joining each bundle to its selected option (lives on the relationship since a child product can be reused across bundles). */
    @TestVisible
    private Map<String, String> queryChildOptionPriceValues(Map<String, BundleStructure> bundleMap) {
        Map<String, String> priceOptionMap = new Map<String, String>();

        Set<Id> parentProductIds = new Set<Id>();
        Set<Id> childProductIds = new Set<Id>();
        for (BundleStructure bundle : bundleMap.values()) {
            if (bundle.productId != null && bundle.productId instanceof Id) {
                parentProductIds.add((Id) bundle.productId);
            }
            for (OptionItem option : bundle.childOptions) {
                if (option.productId != null && option.productId instanceof Id) {
                    childProductIds.add((Id) option.productId);
                }
            }
        }

        System.debug(DEBUG_VERSION + ' - queryChildOptionPriceValues: parentProductIds=' + parentProductIds +
                   ', childProductIds=' + childProductIds);

        if (parentProductIds.isEmpty() || childProductIds.isEmpty()) {
            System.debug(DEBUG_VERSION + ' - No parent/child product IDs found for ProductRelatedComponent lookup');
            return priceOptionMap;
        }

        List<ProductRelatedComponent> components = [
            SELECT ParentProductId, ChildProductId, RES_Price_Option__c
            FROM ProductRelatedComponent
            WHERE ParentProductId IN :parentProductIds
                AND ChildProductId IN :childProductIds
        ];
        System.debug(DEBUG_VERSION + ' - queryChildOptionPriceValues: found ' + components.size() +
                   ' ProductRelatedComponent row(s) for this parent/child scope');

        for (ProductRelatedComponent component : components) {
            String key = buildRelatedComponentKey(component.ParentProductId, component.ChildProductId);
            if (String.isNotBlank(component.RES_Price_Option__c)) {
                priceOptionMap.put(key, component.RES_Price_Option__c);
                System.debug(DEBUG_VERSION + ' - ProductRelatedComponent ' + component.Id + ' (key=' + key +
                           ') has ' + CHILD_PRICE_OPTION_SOURCE_FIELD + ' = ' + component.RES_Price_Option__c);
            } else {
                System.debug(DEBUG_VERSION + ' - ProductRelatedComponent ' + component.Id + ' (key=' + key +
                           ') has a blank ' + CHILD_PRICE_OPTION_SOURCE_FIELD + ', skipping');
            }
        }

        System.debug(DEBUG_VERSION + ' - queryChildOptionPriceValues: returning ' + priceOptionMap.size() + ' entr(y/ies): ' + priceOptionMap);
        return priceOptionMap;
    }

    /** Query each installment's % share of its payment-plan option's price from their joining ProductRelatedComponent. */
    @TestVisible
    private Map<String, Decimal> queryInstallmentPercentages(Map<String, BundleStructure> bundleMap) {
        Map<String, Decimal> percentageMap = new Map<String, Decimal>();

        Set<Id> optionProductIds = new Set<Id>();
        for (BundleStructure bundle : bundleMap.values()) {
            for (OptionItem option : bundle.childOptions) {
                if (option.productId != null && option.productId instanceof Id) {
                    optionProductIds.add((Id) option.productId);
                }
            }
        }

        System.debug(DEBUG_VERSION + ' - queryInstallmentPercentages: optionProductIds=' + optionProductIds);

        if (optionProductIds.isEmpty()) {
            System.debug(DEBUG_VERSION + ' - No option product IDs found for installment percentage lookup');
            return percentageMap;
        }

        List<ProductRelatedComponent> components = [
            SELECT ParentProductId, ChildProductId, RES_Installment_Percentage__c
            FROM ProductRelatedComponent
            WHERE ParentProductId IN :optionProductIds
                AND ChildProductId IN :optionProductIds
                AND RES_Installment_Percentage__c != null
        ];
        System.debug(DEBUG_VERSION + ' - queryInstallmentPercentages: found ' + components.size() +
                   ' ProductRelatedComponent row(s) with an ' + INSTALLMENT_PERCENTAGE_SOURCE_FIELD + ' value');

        for (ProductRelatedComponent component : components) {
            String key = buildRelatedComponentKey(component.ParentProductId, component.ChildProductId);
            percentageMap.put(key, component.RES_Installment_Percentage__c);
            System.debug(DEBUG_VERSION + ' - ProductRelatedComponent ' + component.Id + ' (key=' + key +
                       ') has ' + INSTALLMENT_PERCENTAGE_SOURCE_FIELD + ' = ' + component.RES_Installment_Percentage__c);
        }

        System.debug(DEBUG_VERSION + ' - queryInstallmentPercentages: returning ' + percentageMap.size() + ' entr(y/ies): ' + percentageMap);
        return percentageMap;
    }

    /** Query each bundle's RES_Net_Saleable_Area__c (fixed catalog field, needed for the service charge calc). */
    @TestVisible
    private Map<Id, Decimal> queryNetSaleableAreaByProduct(Map<String, BundleStructure> bundleMap) {
        Map<Id, Decimal> areaMap = new Map<Id, Decimal>();

        Set<Id> bundleProductIds = new Set<Id>();
        for (BundleStructure bundle : bundleMap.values()) {
            if (bundle.productId != null && bundle.productId instanceof Id) {
                bundleProductIds.add((Id) bundle.productId);
            }
        }

        if (bundleProductIds.isEmpty()) {
            System.debug(DEBUG_VERSION + ' - No bundle product IDs found for Net Saleable Area lookup');
            return areaMap;
        }

        for (Product2 product : [
            SELECT Id, RES_Net_Saleable_Area__c
            FROM Product2
            WHERE Id IN :bundleProductIds
                AND RES_Net_Saleable_Area__c != null
        ]) {
            areaMap.put(product.Id, product.RES_Net_Saleable_Area__c);
            System.debug(DEBUG_VERSION + ' - Product ' + product.Id + ' has RES_Net_Saleable_Area__c = ' + product.RES_Net_Saleable_Area__c);
        }

        System.debug(DEBUG_VERSION + ' - queryNetSaleableAreaByProduct: returning ' + areaMap.size() + ' entr(y/ies): ' + areaMap);
        return areaMap;
    }

    /** Identify which child option products are the 'Service Charge' component, matched by Product2.Name. */
    @TestVisible
    private Set<Id> queryServiceChargeProductIds(Map<String, BundleStructure> bundleMap) {
        Set<Id> serviceChargeProductIds = new Set<Id>();

        Set<Id> optionProductIds = new Set<Id>();
        for (BundleStructure bundle : bundleMap.values()) {
            for (OptionItem option : bundle.childOptions) {
                if (option.productId != null && option.productId instanceof Id) {
                    optionProductIds.add((Id) option.productId);
                }
            }
        }

        if (optionProductIds.isEmpty()) {
            System.debug(DEBUG_VERSION + ' - No option product IDs found for service charge component lookup');
            return serviceChargeProductIds;
        }

        for (Product2 product : [
            SELECT Id
            FROM Product2
            WHERE Id IN :optionProductIds
                AND Name = :SERVICE_CHARGE_COMPONENT_NAME
        ]) {
            serviceChargeProductIds.add(product.Id);
        }

        System.debug(DEBUG_VERSION + ' - queryServiceChargeProductIds: found ' + serviceChargeProductIds);
        return serviceChargeProductIds;
    }

    /** Query each bundle's SC_RATE directly from catalog config (ProductAttributeDefinition.DefaultValue), not the live context. */
    @TestVisible
    private Map<Id, Decimal> queryServiceChargeRateByProduct(Map<String, BundleStructure> bundleMap) {
        Map<Id, Decimal> rateMap = new Map<Id, Decimal>();

        Set<Id> bundleProductIds = new Set<Id>();
        for (BundleStructure bundle : bundleMap.values()) {
            if (bundle.productId != null && bundle.productId instanceof Id) {
                bundleProductIds.add((Id) bundle.productId);
            }
        }

        if (bundleProductIds.isEmpty()) {
            System.debug(DEBUG_VERSION + ' - No bundle product IDs found for SC_RATE lookup');
            return rateMap;
        }

        for (ProductAttributeDefinition attrDef : [
            SELECT Product2Id, DefaultValue
            FROM ProductAttributeDefinition
            WHERE Product2Id IN :bundleProductIds
                AND AttributeDefinition.DeveloperName = :SERVICE_CHARGE_RATE_ATTRIBUTE
                AND DefaultValue != null
        ]) {
            if (String.isNotBlank(attrDef.DefaultValue)) {
                rateMap.put(attrDef.Product2Id, Decimal.valueOf(attrDef.DefaultValue));
                System.debug(DEBUG_VERSION + ' - Product ' + attrDef.Product2Id + ' has ' +
                           SERVICE_CHARGE_RATE_ATTRIBUTE + ' = ' + attrDef.DefaultValue);
            }
        }

        System.debug(DEBUG_VERSION + ' - queryServiceChargeRateByProduct: returning ' + rateMap.size() + ' entr(y/ies): ' + rateMap);
        return rateMap;
    }

    /** Key for looking up a ProductRelatedComponent value by parent bundle + child option product pair. */
    @TestVisible
    private String buildRelatedComponentKey(Object parentProductId, Object childProductId) {
        String key = parentProductId + ':' + childProductId;
        System.debug(DEBUG_VERSION + ' - buildRelatedComponentKey: parentProductId=' + parentProductId +
                   ', childProductId=' + childProductId + ' -> key=' + key);
        return key;
    }

    /** Apply pricing adjustments to each selected child option, driven by its own RES_Price_Option__c value. */
    @TestVisible
    private List<Map<String, Object>> applyPricingToOptions(
        Map<String, BundleStructure> bundleMap,
        Map<String, Map<String, String>> itemAttributeMap,
        Map<String, List<AttributeAdjustment>> bundleAdjustmentsMap,
        Map<String, String> relatedComponentPriceOptionMap,
        Map<String, List<Object>> attributeNodePathMap,
        Map<String, Decimal> installmentPercentageMap,
        Map<Id, Decimal> netSaleableAreaMap,
        Set<Id> serviceChargeProductIds,
        Map<Id, Decimal> serviceChargeRateMap
    ) {
        List<Map<String, Object>> allUpdates = new List<Map<String, Object>>();

        for (BundleStructure bundle : bundleMap.values()) {
            // Skip if bundle has no children or no product
            if (bundle.childOptions.isEmpty() || bundle.productId == null) {
                System.debug(DEBUG_VERSION + ' - Skipping bundle ' + bundle.bundleId +
                           ' (no children or product)');
                continue;
            }

            // Service charge = SC_RATE x bundle's Net Saleable Area, written to RES_Service_Charge_Amount__c (never PartnerUnitPrice/InputUnitPrice)
            Decimal serviceChargeAmount = computeServiceCharge(bundle, serviceChargeRateMap, netSaleableAreaMap);
            if (serviceChargeAmount != 0) {
                for (OptionItem candidate : bundle.childOptions) {
                    if (serviceChargeProductIds.contains(candidate.productId)) {
                        allUpdates.add(new Map<String, Object>{
                            'nodePath' => new Map<String, Object>{'dataPath' => candidate.nodePath},
                            'attributes' => new List<Map<String, Object>>{
                                new Map<String, Object>{
                                    'attributeName' => SERVICE_CHARGE_AMOUNT_FIELD,
                                    'attributeValue' => serviceChargeAmount
                                }
                            }
                        });
                        System.debug(DEBUG_VERSION + ' - Applying service charge ' + serviceChargeAmount +
                                   ' to component ' + candidate.lineItemId + ' (bundle ' + bundle.bundleId +
                                   ') via ' + SERVICE_CHARGE_AMOUNT_FIELD);
                    }
                }
            }

            List<AttributeAdjustment> bundleAdjustments = bundleAdjustmentsMap.get(bundle.productId);
            if (bundleAdjustments == null || bundleAdjustments.isEmpty()) {
                System.debug(DEBUG_VERSION + ' - No adjustments defined for bundle product: ' + bundle.productId);
                continue;
            }

            for (OptionItem childOption : bundle.childOptions) {
                String childPriceOptionValue = relatedComponentPriceOptionMap.get(
                    buildRelatedComponentKey(bundle.productId, childOption.productId)
                );
                if (String.isBlank(childPriceOptionValue)) {
                    System.debug(DEBUG_VERSION + ' - Selected option ' + childOption.lineItemId +
                               ' has no ' + CHILD_PRICE_OPTION_SOURCE_FIELD + ' value on its ProductRelatedComponent, skipping');
                    continue;
                }

                System.debug(DEBUG_VERSION + ' - Processing selected option: ' + childOption.lineItemId +
                           ', ' + CHILD_PRICE_OPTION_SOURCE_FIELD + ': ' + childPriceOptionValue);

                // Mirror the selection onto an existing Pricing_Option attribute node if one exists (can only update, never create)
                List<Object> priceOptionAttrNodePath = attributeNodePathMap.get(
                    bundle.bundleId + ':' + PRICE_OPTION_MATCHING_ATTRIBUTE
                );
                if (priceOptionAttrNodePath != null) {
                    allUpdates.add(new Map<String, Object>{
                        'nodePath' => new Map<String, Object>{'dataPath' => priceOptionAttrNodePath},
                        'attributes' => new List<Map<String, Object>>{
                            new Map<String, Object>{
                                'attributeName' => 'AttributeValue',
                                'attributeValue' => childPriceOptionValue
                            }
                        }
                    });
                    System.debug(DEBUG_VERSION + ' - Updating existing ' + PRICE_OPTION_MATCHING_ATTRIBUTE +
                               ' attribute node on bundle ' + bundle.bundleId + ' to ' + childPriceOptionValue);
                } else {
                    System.debug(DEBUG_VERSION + ' - No existing ' + PRICE_OPTION_MATCHING_ATTRIBUTE +
                               ' attribute node found on bundle ' + bundle.bundleId + ', cannot mirror the selection onto it');
                }

                // Build the matching context: this option's price-option value plus any extra attributes for AND matching
                Map<String, String> matchContext = new Map<String, String>();
                if (itemAttributeMap.get(childOption.lineItemId) != null) {
                    matchContext.putAll(itemAttributeMap.get(childOption.lineItemId));
                }
                matchContext.put(PRICE_OPTION_MATCHING_ATTRIBUTE, childPriceOptionValue);

                List<AttributeAdjustment> matchingAdjustments = findMatchingAdjustments(bundleAdjustments, matchContext);

                if (matchingAdjustments.isEmpty()) {
                    System.debug(DEBUG_VERSION + ' - No matching adjustment for ' + CHILD_PRICE_OPTION_SOURCE_FIELD +
                               ': ' + childPriceOptionValue);
                    continue;
                }

                for (AttributeAdjustment adjustment : matchingAdjustments) {
                    if (shouldApplyToOption(adjustment, childOption, matchContext)) {
                        // Apply the price to the BUNDLE's own line, not the option's - service charge is handled separately above
                        Map<String, Object> updateNode = buildPriceUpdateNode(bundle.nodePath, adjustment);

                        if (updateNode != null) {
                            allUpdates.add(updateNode);
                            System.debug(DEBUG_VERSION + ' - Applying adjustment "' + adjustment.name +
                                       '" to bundle ' + bundle.bundleId +
                                       ' (selected option: ' + childOption.lineItemId + ')' +
                                       ' [' + adjustment.adjustmentType + ' = ' + adjustment.adjustmentValue + ']');
                        }

                        // Display-only installment percentage/amount fields - never read by pricing, so never double-counted
                        allUpdates.addAll(buildInstallmentDisplayUpdates(
                            bundle, childOption, adjustment.adjustmentValue, installmentPercentageMap
                        ));
                    }
                }
            }
        }

        return allUpdates;
    }

    /** Build display-only updates for each installment child of the selected option (identified via lineItemPath). */
    @TestVisible
    private List<Map<String, Object>> buildInstallmentDisplayUpdates(
        BundleStructure bundle,
        OptionItem selectedOption,
        Decimal optionAdjustmentValue,
        Map<String, Decimal> installmentPercentageMap
    ) {
        List<Map<String, Object>> updates = new List<Map<String, Object>>();

        for (OptionItem candidate : bundle.childOptions) {
            if (candidate.lineItemPath == null) {
                continue;
            }
            List<String> pathSegments = candidate.lineItemPath.split('/');
            if (pathSegments.size() < 2) {
                continue;
            }
            String immediateParentRef = pathSegments[pathSegments.size() - 2];
            if (immediateParentRef != selectedOption.lineItemId) {
                continue;
            }

            Decimal percentage = installmentPercentageMap.get(
                buildRelatedComponentKey(selectedOption.productId, candidate.productId)
            );
            if (percentage == null) {
                System.debug(DEBUG_VERSION + ' - Installment ' + candidate.lineItemId +
                           ' has no ' + INSTALLMENT_PERCENTAGE_SOURCE_FIELD + ' on its ProductRelatedComponent, skipping');
                continue;
            }

            Decimal installmentAmount = optionAdjustmentValue * (percentage / 100);

            Map<String, Object> installmentUpdateNode = buildInstallmentDisplayUpdateNode(
                candidate.nodePath, percentage, installmentAmount
            );
            if (installmentUpdateNode != null) {
                updates.add(installmentUpdateNode);
                System.debug(DEBUG_VERSION + ' - Installment ' + candidate.lineItemId + ' = ' +
                           percentage + '% of ' + optionAdjustmentValue + ' = ' + installmentAmount);
            }
        }

        return updates;
    }

    /** Build the update node for an installment's display-only percentage/amount fields (never affects pricing). */
    @TestVisible
    private Map<String, Object> buildInstallmentDisplayUpdateNode(
        List<Object> nodePath,
        Decimal percentage,
        Decimal amount
    ) {
        if (nodePath == null || nodePath.isEmpty()) {
            System.debug(DEBUG_VERSION + ' - Invalid nodePath, cannot build installment display update node');
            return null;
        }

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{'dataPath' => nodePath},
            'attributes' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'attributeName' => 'RES_Installment_Percentage__c',
                    'attributeValue' => percentage
                },
                new Map<String, Object>{
                    'attributeName' => 'RES_Installment_Amount__c',
                    'attributeValue' => amount
                }
            }
        };
    }

    /** Find adjustments whose conditions match the given context. */
    @TestVisible
    private List<AttributeAdjustment> findMatchingAdjustments(
        List<AttributeAdjustment> adjustments,
        Map<String, String> matchContext
    ) {
        List<AttributeAdjustment> matches = new List<AttributeAdjustment>();

        for (AttributeAdjustment adjustment : adjustments) {
            if (adjustment.matchesAllConditions(matchContext)) {
                matches.add(adjustment);
                System.debug(DEBUG_VERSION + ' - Found matching adjustment: ' + adjustment.name +
                           ' (matched ' + (adjustment.conditions != null ? adjustment.conditions.size() : 0) + ' conditions)');
            }
        }

        return matches;
    }

    /** Determine if an adjustment should apply to a specific child option. */
    @TestVisible
    private Boolean shouldApplyToOption(
        AttributeAdjustment adjustment,
        OptionItem childOption,
        Map<String, String> childAttributes
    ) {
        System.debug(DEBUG_VERSION + ' - shouldApplyToOption: adjustment=' + adjustment.name +
                   ', appliesTo=' + adjustment.appliesTo + ', option=' + childOption.lineItemId +
                   ', optionProduct=' + childOption.productId);

        // If adjustment has an 'AppliesTo' criteria, check it
        if (String.isNotBlank(adjustment.appliesTo)) {
            // Check if it matches child product
            if (adjustment.appliesTo.equals(childOption.productId)) {
                System.debug(DEBUG_VERSION + ' - shouldApplyToOption: matched on child product, applying');
                return true;
            }

            // Check if it matches any child attribute
            if (childAttributes != null) {
                for (String attrValue : childAttributes.values()) {
                    if (adjustment.appliesTo.equals(attrValue)) {
                        System.debug(DEBUG_VERSION + ' - shouldApplyToOption: matched on child attribute value, applying');
                        return true;
                    }
                }
            }

            System.debug(DEBUG_VERSION + ' - shouldApplyToOption: no match against appliesTo, skipping');
            return false;
        }

        // If no specific AppliesTo criteria, apply to all child options
        System.debug(DEBUG_VERSION + ' - shouldApplyToOption: no appliesTo criteria, applying to all options');
        return true;
    }

    /** Build context update node to set pricing on the option (delegates to the bundle-nodePath overload). */
    @TestVisible
    private Map<String, Object> buildPriceUpdateNode(
        OptionItem childOption,
        AttributeAdjustment adjustment
    ) {
        return buildPriceUpdateNode(childOption.nodePath, adjustment);
    }

    /** Build context update node to set pricing at the bundle's own line (so its price changes on option selection). */
    @TestVisible
    private Map<String, Object> buildPriceUpdateNode(
        List<Object> nodePath,
        AttributeAdjustment adjustment
    ) {
        if (nodePath == null || nodePath.isEmpty()) {
            System.debug(DEBUG_VERSION + ' - Invalid nodePath, cannot build price update node');
            return null;
        }

        List<Map<String, Object>> attributes = new List<Map<String, Object>>();

        // Map adjustment type to context attribute
        if (adjustment.adjustmentType == 'Percentage') {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'AdjustmentPercent',
                'attributeValue' => adjustment.adjustmentValue
            });
        } else if (adjustment.adjustmentType == 'Override') {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'PartnerUnitPrice',
                'attributeValue' => adjustment.adjustmentValue
            });
        } else if (adjustment.adjustmentType == 'Amount') {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'AdjustmentAmount',
                'attributeValue' => adjustment.adjustmentValue
            });
        } else {
            System.debug(DEBUG_VERSION + ' - Unsupported adjustment type: ' + adjustment.adjustmentType);
            return null;
        }

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{'dataPath' => nodePath},
            'attributes' => attributes
        };
    }

    /** Compute service charge: SC_RATE x bundle's RES_Net_Saleable_Area__c. Returns 0 if either input is missing. */
    @TestVisible
    private Decimal computeServiceCharge(
        BundleStructure bundle,
        Map<Id, Decimal> serviceChargeRateMap,
        Map<Id, Decimal> netSaleableAreaMap
    ) {
        Decimal rate = bundle.productId instanceof Id ? serviceChargeRateMap.get((Id) bundle.productId) : null;
        Decimal netSaleableArea = bundle.productId instanceof Id ? netSaleableAreaMap.get((Id) bundle.productId) : null;

        if (rate == null || netSaleableArea == null) {
            System.debug(DEBUG_VERSION + ' - computeServiceCharge: missing ' + SERVICE_CHARGE_RATE_ATTRIBUTE +
                       ' (' + rate + ') or RES_Net_Saleable_Area__c (' + netSaleableArea + ') for bundle ' +
                       bundle.bundleId + ', service charge = 0');
            return 0;
        }

        Decimal serviceCharge = rate * netSaleableArea;
        System.debug(DEBUG_VERSION + ' - computeServiceCharge: bundle ' + bundle.bundleId + ' = ' +
                   rate + ' x ' + netSaleableArea + ' = ' + serviceCharge);
        return serviceCharge;
    }

    /** Extract a tag value from a context tag map. */
    @TestVisible
    private String getTagValue(Map<String, Object> tagMap, String tagName) {
        if (tagMap != null && tagMap.containsKey(tagName)) {
            Map<String, Object> tag = (Map<String, Object>)tagMap.get(tagName);
            if (tag != null && tag.containsKey('tagValue')) {
                String value = (String)tag.get('tagValue');
                System.debug(DEBUG_VERSION + ' - getTagValue: ' + tagName + ' = ' + value);
                return value;
            }
        }
        System.debug(DEBUG_VERSION + ' - getTagValue: ' + tagName + ' not found');
        return null;
    }

    /** Get DML status from a tag value map. */
    @TestVisible
    private String getDmlStatus(Map<String, Object> tagValue) {
        if (tagValue.containsKey('LineItemPath')) {
            Map<String, Object> lineItemPathTag = (Map<String, Object>)tagValue.get('LineItemPath');
            if (lineItemPathTag != null && lineItemPathTag.containsKey('dmlStatus')) {
                String status = (String)lineItemPathTag.get('dmlStatus');
                System.debug(DEBUG_VERSION + ' - getDmlStatus: from LineItemPath = ' + status);
                return status;
            }
        }
        if (tagValue.containsKey('LineItem')) {
            Map<String, Object> lineItemTag = (Map<String, Object>)tagValue.get('LineItem');
            if (lineItemTag != null && lineItemTag.containsKey('dmlStatus')) {
                String status = (String)lineItemTag.get('dmlStatus');
                System.debug(DEBUG_VERSION + ' - getDmlStatus: from LineItem = ' + status);
                return status;
            }
        }
        System.debug(DEBUG_VERSION + ' - getDmlStatus: no dmlStatus found');
        return null;
    }

    // ========== Inner Classes ==========

    /** Represents a bundle and its child options. */
    @TestVisible
    private class BundleStructure {
        @TestVisible String bundleId;
        @TestVisible String productId;
        @TestVisible List<Object> nodePath;
        @TestVisible List<OptionItem> childOptions;

        @TestVisible
        BundleStructure(String bundleId, String productId) {
            this.bundleId = bundleId;
            this.productId = productId;
            this.childOptions = new List<OptionItem>();
        }

        @TestVisible
        void addChildOption(OptionItem option) {
            this.childOptions.add(option);
        }
    }

    /** Represents a child option in a bundle. */
    @TestVisible
    private class OptionItem {
        @TestVisible String lineItemId;
        @TestVisible String productId;
        List<Object> nodePath;
        String lineItemPath;

        @TestVisible
        OptionItem(String lineItemId, String productId, List<Object> nodePath, String lineItemPath) {
            this.lineItemId = lineItemId;
            this.productId = productId;
            this.nodePath = nodePath;
            this.lineItemPath = lineItemPath;
        }
    }

    /** An attribute-based pricing adjustment with its matching conditions from the related rule. */
    @TestVisible
    private class AttributeAdjustment {
        @TestVisible String adjustmentId;
        @TestVisible String name;
        @TestVisible String adjustmentType;   // 'Override' | 'Percentage' | 'Amount'
        @TestVisible Decimal adjustmentValue;
        @TestVisible String appliesTo;        // optional per-option restriction (see shouldApplyToOption)
        @TestVisible List<AttributeAdjustmentCondition> conditions;

        @TestVisible
        AttributeAdjustment(
            String id, String name, String adjType, Decimal adjValue,
            String appliesTo, List<AttributeAdjustmentCondition> conditions
        ) {
            this.adjustmentId = id;
            this.name = name;
            this.adjustmentType = adjType;
            this.adjustmentValue = adjValue;
            this.appliesTo = appliesTo;
            this.conditions = conditions != null ? conditions : new List<AttributeAdjustmentCondition>();
        }

        /** Check if all conditions match the given attributes (AND logic) by AttributeDefinition DeveloperName. */
        @TestVisible
        Boolean matchesAllConditions(Map<String, String> itemAttributes) {
            System.debug(DEBUG_VERSION + ' - matchesAllConditions: evaluating adjustment "' + this.name +
                       '" against itemAttributes=' + itemAttributes);

            if (this.conditions == null || this.conditions.isEmpty()) {
                System.debug(DEBUG_VERSION + ' - matchesAllConditions: adjustment "' + this.name +
                           '" has no conditions, cannot match');
                return false;
            }

            for (AttributeAdjustmentCondition condition : this.conditions) {
                String attributeName = condition.AttributeDefinition != null
                    ? condition.AttributeDefinition.DeveloperName
                    : null;

                System.debug(DEBUG_VERSION + ' - matchesAllConditions: condition ' + condition.Id +
                           ' targets attribute=' + attributeName + ', operator=' + condition.Operator +
                           ', expectedValue=' + condition.StringValue);

                if (attributeName == null || !itemAttributes.containsKey(attributeName)) {
                    System.debug(DEBUG_VERSION + ' - matchesAllConditions: attribute ' + attributeName +
                               ' missing from itemAttributes, no match for adjustment "' + this.name + '"');
                    return false;
                }

                if (!conditionMatchesValue(condition, itemAttributes.get(attributeName))) {
                    System.debug(DEBUG_VERSION + ' - matchesAllConditions: value mismatch for attribute ' +
                               attributeName + ', no match for adjustment "' + this.name + '"');
                    return false;
                }
            }

            System.debug(DEBUG_VERSION + ' - matchesAllConditions: all conditions matched for adjustment "' + this.name + '"');
            return true;
        }

        private Boolean conditionMatchesValue(AttributeAdjustmentCondition condition, String itemValue) {
            if (itemValue == null) {
                System.debug(DEBUG_VERSION + ' - conditionMatchesValue: itemValue is null, no match');
                return false;
            }

            Boolean result;
            if (condition.Operator == OPERATOR_EQUALS) {
                result = itemValue.equals(condition.StringValue);
            } else if (condition.Operator == OPERATOR_NOT_EQUALS) {
                result = !itemValue.equals(condition.StringValue);
            } else {
                System.debug(DEBUG_VERSION + ' - Unsupported operator for text-attribute matching: ' + condition.Operator);
                return false;
            }

            System.debug(DEBUG_VERSION + ' - conditionMatchesValue: itemValue=' + itemValue +
                       ', operator=' + condition.Operator + ', expectedValue=' + condition.StringValue +
                       ' -> result=' + result);
            return result;
        }
    }
}
