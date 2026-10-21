/**
 * @description Invocable backend for the "Create Payment Plan" screen flow (RES_Create_Payment_Plan),
 * launched from the Product2 list view for non-admin Revenue Cloud catalog configurators.
 *
 * Creates a full Residential Payment Plan bundle in one transaction: the Payment Plan Product2
 * (Type = 'Bundle'), a ProductComponentGroup, one Installment Product2 per row the user defined,
 * the ProductRelatedComponent rows linking them (carrying the authoritative
 * RES_Installment_Percentage__c that RES_ResidentialBundlePricingHook reads at quote time), a
 * PricebookEntry per product on both the Standard Price Book and the Residential Sales pricebook,
 * and a ProductSellingModelOption per product on the org's "One-Time" selling model.
 *
 * All DML is wrapped in a savepoint so a failure partway through never leaves a half-built bundle
 * behind - the exact gap this flow exists to close (see the org's own incomplete sample bundle,
 * "WS 5-Year Construction-Linked 15/80", which has no PricebookEntry or ProductSellingModelOption
 * rows at all).
 */
public with sharing class RES_PaymentPlanConfiguratorService {

    private static final String PAYMENT_PLAN_RECORD_TYPE_DEV_NAME = 'RES_Residential_Payment_Plan';
    private static final String INSTALLMENT_RECORD_TYPE_DEV_NAME = 'RES_Residential_Installment';
    private static final String CIP_TYPE_PAYMENT_PLAN = 'Payment Plan';
    private static final String CIP_TYPE_INSTALLMENT = 'Installment';
    private static final String BUNDLE_COMPONENT_RELATIONSHIP_TYPE_NAME = 'Bundle to Bundle Component Relationship';
    private static final String ONE_TIME_SELLING_MODEL_NAME = 'One-Time';
    private static final String RESIDENTIAL_SALES_PRICEBOOK_NAME = 'Residential Sales';
    private static final Decimal PERCENTAGE_TOTAL_TOLERANCE = 0.01;
    private static final Decimal PERCENTAGE_TOTAL_TARGET = 100;
    private static final Integer MONTHS_PER_YEAR = 12;
    private static final String STATUS_ROLE_RELEASED = 'REL';
    private static final String STATUS_ROLE_DESCRIPTION_RELEASED = 'Released';
    private static final String PHASE_ON_PLAN = 'On-Plan';
    private static final String PHASE_OFF_PLAN = 'Off-Plan';
    private static final Decimal ON_PLAN_POC_PERCENTAGE = 100;

    public class PaymentPlanConfiguratorException extends Exception {}

    /**
     * Input collected across both screens of the flow. Scalar Payment Plan fields come from
     * native flow screen components on screen 1; installmentsJson is produced by the
     * resPaymentPlanInstallments LWC screen component on screen 2 (a JSON array, one object per
     * installment row, since a repeating editable grid isn't something a native Flow screen can
     * express and an Apex-defined Flow data type would be more brittle to hand-maintain here).
     */
    public class Request {
        @InvocableVariable(label='Payment Plan Name' required=true)
        public String planName;

        @InvocableVariable(label='Product Code')
        public String productCode;

        @InvocableVariable(label='Number of Years')
        public Decimal numberOfYears;

        @InvocableVariable(label='Catalog Id')
        public Id catalogId;

        @InvocableVariable(label='Currency ISO Code')
        public String currencyIsoCode;

        @InvocableVariable(label='Price Option' required=true)
        public String priceOption;

        @InvocableVariable(label='Valid From' required=true)
        public Date validFromDate;

        @InvocableVariable(label='Valid To')
        public Date validToDate;

        @InvocableVariable(label='Is Active')
        public Boolean isActive;

        @InvocableVariable(label='Description')
        public String description;

        @InvocableVariable(label='Is Assetizable')
        public Boolean isAssetizable;

        @InvocableVariable(label='Installments (JSON)' required=true)
        public String installmentsJson;
    }

    public class Result {
        @InvocableVariable public Boolean isSuccess;
        @InvocableVariable public String message;
        @InvocableVariable public Id paymentPlanId;
        @InvocableVariable public Integer installmentCount;
    }

    /**
     * One row of the installment table built by the LWC. Fields are public (not private) so
     * JSON.deserialize can populate them directly. dueDate is never trusted from the client: it is
     * recalculated as Valid From + conditionMonths + conditionDays.
     */
    @TestVisible
    private class InstallmentInput {
        public Decimal percentage;
        public Decimal pocPercentage;
        public Date dueDate;
        public String conditionType;
        public Integer conditionMonths;
        public Integer conditionDays;
        public Integer sequence;
    }

    @InvocableMethod(
        label='Create Payment Plan'
        description='Creates a Residential Payment Plan bundle product with Installment components, ProductRelatedComponent links, PricebookEntry rows, and ProductSellingModelOption rows.'
        category='Revenue Cloud'
    )
    public static List<Result> createPaymentPlan(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(createSinglePaymentPlan(req));
        }
        return results;
    }

    private static Result createSinglePaymentPlan(Request req) {
        Result res = new Result();
        Savepoint sp = Database.setSavepoint();
        try {
            List<InstallmentInput> installments = parseInstallments(req.installmentsJson);
            String developmentPhase = developmentPhase(req.catalogId);
            validate(req, installments, developmentPhase);

            Id paymentPlanId = insertPaymentPlan(req);
            Id groupId = insertComponentGroup(paymentPlanId, req.planName, installments.size());
            List<Id> installmentIds = insertInstallments(req, installments, developmentPhase);
            insertRelatedComponents(paymentPlanId, groupId, installments, installmentIds);

            List<Id> allProductIds = new List<Id>{ paymentPlanId };
            allProductIds.addAll(installmentIds);
            // Installments are always inserted active; the Payment Plan itself may not be - an active PricebookEntry on an inactive product throws FIELD_INTEGRITY_EXCEPTION
            Set<Id> activeProductIds = new Set<Id>(installmentIds);
            if (req.isActive == true) {
                activeProductIds.add(paymentPlanId);
            }
            Id sellingModelId = oneTimeSellingModelId();
            insertSellingModelOptions(allProductIds, sellingModelId);
            insertPricebookEntries(allProductIds, activeProductIds, sellingModelId);

            res.isSuccess = true;
            res.paymentPlanId = paymentPlanId;
            res.installmentCount = installments.size();
            res.message = 'Payment Plan "' + req.planName + '" created with ' + installments.size() + ' installment(s).';
        } catch (Exception e) {
            Database.rollback(sp);
            res.isSuccess = false;
            res.message = e.getMessage();
        }
        return res;
    }

    @TestVisible
    private static List<InstallmentInput> parseInstallments(String installmentsJson) {
        if (String.isBlank(installmentsJson)) {
            throw new PaymentPlanConfiguratorException('At least one installment is required.');
        }
        try {
            return (List<InstallmentInput>) JSON.deserialize(installmentsJson, List<InstallmentInput>.class);
        } catch (Exception e) {
            throw new PaymentPlanConfiguratorException('Could not read the installment table: ' + e.getMessage());
        }
    }

    @TestVisible
    private static void validate(Request req, List<InstallmentInput> installments, String developmentPhase) {
        if (String.isBlank(req.planName)) {
            throw new PaymentPlanConfiguratorException('Payment Plan Name is required.');
        }
        if (req.validFromDate == null) {
            throw new PaymentPlanConfiguratorException('Valid From is required.');
        }
        if (req.validToDate != null && req.validToDate < req.validFromDate) {
            throw new PaymentPlanConfiguratorException('Valid To cannot be before Valid From.');
        }
        if (String.isBlank(req.priceOption)) {
            throw new PaymentPlanConfiguratorException('Price Option is required.');
        }
        if (developmentPhase == PHASE_ON_PLAN && req.numberOfYears == null) {
            throw new PaymentPlanConfiguratorException('Number of Years is required for an On-Plan catalog.');
        }
        if (installments.isEmpty()) {
            throw new PaymentPlanConfiguratorException('At least one installment is required.');
        }

        Set<Integer> seenSequences = new Set<Integer>();
        Map<String, Integer> seenConditionKeys = new Map<String, Integer>();
        Decimal totalPercentage = 0;
        Date planStart = req.validFromDate;
        Integer maxMonths = monthsFor(req.numberOfYears);
        Date latestDueDate = maxMonths != null ? planStart.addMonths(maxMonths) : null;
        InstallmentInput previous;
        for (InstallmentInput installment : installments) {
            if (installment.sequence == null) {
                throw new PaymentPlanConfiguratorException('Every installment must have a sequence.');
            }
            if (seenSequences.contains(installment.sequence)) {
                throw new PaymentPlanConfiguratorException('Installment sequence ' + installment.sequence + ' is used more than once.');
            }
            seenSequences.add(installment.sequence);

            if (installment.percentage == null || installment.percentage <= 0 || installment.percentage > 100) {
                throw new PaymentPlanConfiguratorException('Installment ' + installment.sequence + ' must have a percentage greater than 0 and no more than 100.');
            }
            totalPercentage += installment.percentage;

            applyPocRule(installment, developmentPhase);
            validateCondition(installment, previous, planStart, latestDueDate, maxMonths, seenConditionKeys);
            previous = installment;
        }

        if (Math.abs(totalPercentage - PERCENTAGE_TOTAL_TARGET) > PERCENTAGE_TOTAL_TOLERANCE) {
            throw new PaymentPlanConfiguratorException('Installment percentages must add up to 100% (currently ' + totalPercentage + '%).');
        }

        if (String.isNotBlank(req.productCode) && productCodeInUse(req.productCode)) {
            throw new PaymentPlanConfiguratorException('Product Code "' + req.productCode + '" is already in use by another product.');
        }
    }

    // On-Plan fixes POC at 100%; Off-Plan requires a POC on every installment
    private static void applyPocRule(InstallmentInput installment, String developmentPhase) {
        if (developmentPhase == PHASE_ON_PLAN) {
            installment.pocPercentage = ON_PLAN_POC_PERCENTAGE;
        } else if (developmentPhase == PHASE_OFF_PLAN && (installment.pocPercentage == null || installment.pocPercentage < 0 || installment.pocPercentage > 100)) {
            throw new PaymentPlanConfiguratorException('Installment ' + installment.sequence + ' must have a POC % between 0 and 100 for an Off-Plan catalog.');
        }
    }

    // Due date = Valid From + condition months/days; due dates must not go backwards, must stay within Number of Years, and can't repeat for the same condition type
    private static void validateCondition(InstallmentInput installment, InstallmentInput previous, Date planStart, Date latestDueDate,
            Integer maxMonths, Map<String, Integer> seenConditionKeys) {
        if (String.isBlank(installment.conditionType)) {
            throw new PaymentPlanConfiguratorException('Installment ' + installment.sequence + ' must have an Installment Type.');
        }
        if (installment.conditionMonths == null || installment.conditionMonths < 0) {
            throw new PaymentPlanConfiguratorException('Installment ' + installment.sequence + ' must have Condition Months of 0 or more.');
        }
        if (installment.conditionDays == null) {
            installment.conditionDays = 0;
        } else if (installment.conditionDays < 0) {
            throw new PaymentPlanConfiguratorException('Installment ' + installment.sequence + ' cannot have negative Condition Days.');
        }
        installment.dueDate = planStart.addMonths(installment.conditionMonths).addDays(installment.conditionDays);

        if (previous != null && installment.dueDate < previous.dueDate) {
            throw new PaymentPlanConfiguratorException('Installment ' + installment.sequence + ' cannot fall before installment ' + previous.sequence +
                ' (' + previous.conditionMonths + ' months, ' + previous.conditionDays + ' days).');
        }
        if (latestDueDate != null && installment.dueDate > latestDueDate) {
            throw new PaymentPlanConfiguratorException('Installment ' + installment.sequence + ' (' + installment.conditionMonths + ' months, ' +
                installment.conditionDays + ' days) goes beyond the plan\'s Number of Years: Condition Months/Days cannot exceed ' + maxMonths + ' months.');
        }

        String conditionKey = installment.conditionType + '|' + installment.dueDate;
        if (seenConditionKeys.containsKey(conditionKey)) {
            throw new PaymentPlanConfiguratorException('Installments ' + seenConditionKeys.get(conditionKey) + ' and ' + installment.sequence +
                ' have the same Installment Type (' + conditionTypeLabel(installment.conditionType) + ') and the same Condition Months/Days.');
        }
        seenConditionKeys.put(conditionKey, installment.sequence);
    }

    // Number of Years can carry decimals (e.g. 2.5); months are rounded to the nearest whole month
    @TestVisible
    private static Integer monthsFor(Decimal numberOfYears) {
        return numberOfYears == null ? null : (numberOfYears * MONTHS_PER_YEAR).setScale(0, System.RoundingMode.HALF_UP).intValue();
    }

    private static String developmentPhase(Id catalogId) {
        if (catalogId == null) {
            return null;
        }
        List<ProductCatalog> catalogs = [SELECT RES_Development_Phase__c FROM ProductCatalog WHERE Id = :catalogId LIMIT 1];
        return catalogs.isEmpty() ? null : catalogs[0].RES_Development_Phase__c;
    }

    private static String conditionTypeLabel(String conditionType) {
        for (Schema.PicklistEntry entry : Product2.RES_Condition_Type__c.getDescribe().getPicklistValues()) {
            if (entry.getValue() == conditionType) {
                return entry.getLabel();
            }
        }
        return conditionType;
    }

    private static Boolean productCodeInUse(String productCode) {
        return [SELECT COUNT() FROM Product2 WHERE ProductCode = :productCode] > 0;
    }

    private static Id insertPaymentPlan(Request req) {
        Product2 plan = new Product2(
            Name = req.planName,
            ProductCode = req.productCode,
            RecordTypeId = recordTypeId(PAYMENT_PLAN_RECORD_TYPE_DEV_NAME),
            Type = 'Bundle',
            ConfigureDuringSale = 'Allowed',
            RES_CIP_Type__c = CIP_TYPE_PAYMENT_PLAN,
            RES_No_of_Years__c = req.numberOfYears,
            RES_No_of_Months__c = monthsFor(req.numberOfYears),
            RES_Status_Role__c = STATUS_ROLE_RELEASED,
            RES_Status_Role_Description__c = STATUS_ROLE_DESCRIPTION_RELEASED,
            RES_Business_Entity__c = req.catalogId,
            RES_Price_Option__c = req.priceOption,
            CurrencyIsoCode = String.isNotBlank(req.currencyIsoCode) ? req.currencyIsoCode : UserInfo.getDefaultCurrency(),
            AvailabilityDate = req.validFromDate,
            RES_Validity_End_Date__c = req.validToDate,
            IsActive = req.isActive != null ? req.isActive : false,
            Description = req.description,
            IsAssetizable = req.isAssetizable != null ? req.isAssetizable : false
        );
        insert plan;
        return plan.Id;
    }

    private static Id insertComponentGroup(Id paymentPlanId, String planName, Integer installmentCount) {
        ProductComponentGroup componentGroup = new ProductComponentGroup(
            Name = planName + ' Installments',
            ParentProductId = paymentPlanId,
            MinBundleComponents = installmentCount,
            MaxBundleComponents = installmentCount,
            Sequence = 10
        );
        insert componentGroup;
        return componentGroup.Id;
    }

    // Off-Plan due dates are fixed now; On-Plan due dates depend on when the plan is configured on a quote, so none is stored
    private static List<Id> insertInstallments(Request req, List<InstallmentInput> installments, String developmentPhase) {
        Id installmentRecordTypeId = recordTypeId(INSTALLMENT_RECORD_TYPE_DEV_NAME);
        String currencyIsoCode = String.isNotBlank(req.currencyIsoCode) ? req.currencyIsoCode : UserInfo.getDefaultCurrency();

        List<Product2> installmentProducts = new List<Product2>();
        for (InstallmentInput installment : installments) {
            installmentProducts.add(new Product2(
                Name = conditionTypeLabel(installment.conditionType),
                ProductCode = String.isNotBlank(req.productCode) ? (req.productCode + '-INST' + installment.sequence) : null,
                RecordTypeId = installmentRecordTypeId,
                RES_CIP_Type__c = CIP_TYPE_INSTALLMENT,
                RES_Sequence__c = installment.sequence,
                RES_POC_Percentage__c = installment.pocPercentage,
                RES_Installment_Percentage__c = installment.percentage,
                RES_Instalment_DueDate__c = developmentPhase == PHASE_ON_PLAN ? null : installment.dueDate,
                RES_Condition_Type__c = installment.conditionType,
                RES_Installment_Payment_Type__c = installment.conditionType,
                RES_Condition_Months__c = installment.conditionMonths,
                RES_Condition_Days__c = installment.conditionDays,
                CurrencyIsoCode = currencyIsoCode,
                IsActive = true,
                ConfigureDuringSale = 'NotAllowed'
            ));
        }
        insert installmentProducts;

        List<Id> installmentIds = new List<Id>();
        for (Product2 p : installmentProducts) {
            installmentIds.add(p.Id);
        }
        return installmentIds;
    }

    private static void insertRelatedComponents(Id paymentPlanId, Id groupId, List<InstallmentInput> installments, List<Id> installmentIds) {
        Id relationshipTypeId = bundleComponentRelationshipTypeId();

        List<ProductRelatedComponent> components = new List<ProductRelatedComponent>();
        for (Integer i = 0; i < installments.size(); i++) {
            InstallmentInput installment = installments[i];
            components.add(new ProductRelatedComponent(
                ParentProductId = paymentPlanId,
                ChildProductId = installmentIds[i],
                ProductComponentGroupId = groupId,
                ProductRelationshipTypeId = relationshipTypeId,
                Quantity = 1,
                IsComponentRequired = true,
                IsDefaultComponent = true,
                IsQuantityEditable = false,
                DoesBundlePriceIncludeChild = true,
                QuoteVisibility = 'Always',
                Sequence = installment.sequence * 10,
                RES_Installment_Percentage__c = installment.percentage
            ));
        }
        insert components;
    }

    private static void insertPricebookEntries(List<Id> productIds, Set<Id> activeProductIds, Id sellingModelId) {
        Id standardPricebookId = Test.isRunningTest() ? Test.getStandardPricebookId() : standardPricebookId();
        Id residentialSalesPricebookId = pricebookId(RESIDENTIAL_SALES_PRICEBOOK_NAME);

        List<PricebookEntry> standardEntries = new List<PricebookEntry>();
        for (Id productId : productIds) {
            standardEntries.add(new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = productId,
                ProductSellingModelId = sellingModelId,
                UnitPrice = 0,
                IsActive = activeProductIds.contains(productId)
            ));
        }
        insert standardEntries;

        if (residentialSalesPricebookId != null) {
            List<PricebookEntry> customEntries = new List<PricebookEntry>();
            for (Id productId : productIds) {
                customEntries.add(new PricebookEntry(
                    Pricebook2Id = residentialSalesPricebookId,
                    Product2Id = productId,
                    ProductSellingModelId = sellingModelId,
                    UnitPrice = 0,
                    IsActive = activeProductIds.contains(productId),
                    UseStandardPrice = false
                ));
            }
            insert customEntries;
        }
    }

    private static void insertSellingModelOptions(List<Id> productIds, Id sellingModelId) {
        if (sellingModelId == null) {
            return;
        }

        List<ProductSellingModelOption> options = new List<ProductSellingModelOption>();
        for (Id productId : productIds) {
            options.add(new ProductSellingModelOption(
                Product2Id = productId,
                ProductSellingModelId = sellingModelId,
                IsDefault = true
            ));
        }
        insert options;
    }

    // ---- Lookups (by Name/DeveloperName, never hardcoded Ids) ----

    private static Id recordTypeId(String developerName) {
        Schema.RecordTypeInfo info = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName().get(developerName);
        if (info == null) {
            throw new PaymentPlanConfiguratorException('Product2 record type "' + developerName + '" was not found.');
        }
        return info.getRecordTypeId();
    }

    private static Id bundleComponentRelationshipTypeId() {
        List<ProductRelationshipType> types = [
            SELECT Id FROM ProductRelationshipType WHERE Name = :BUNDLE_COMPONENT_RELATIONSHIP_TYPE_NAME LIMIT 1
        ];
        if (types.isEmpty()) {
            throw new PaymentPlanConfiguratorException('Product Relationship Type "' + BUNDLE_COMPONENT_RELATIONSHIP_TYPE_NAME + '" was not found.');
        }
        return types[0].Id;
    }

    private static Id standardPricebookId() {
        List<Pricebook2> books = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        if (books.isEmpty()) {
            throw new PaymentPlanConfiguratorException('No Standard Price Book was found.');
        }
        return books[0].Id;
    }

    private static Id pricebookId(String name) {
        List<Pricebook2> books = [SELECT Id FROM Pricebook2 WHERE Name = :name AND IsActive = true LIMIT 1];
        return books.isEmpty() ? null : books[0].Id;
    }

    private static Id oneTimeSellingModelId() {
        List<ProductSellingModel> models = [
            SELECT Id FROM ProductSellingModel WHERE Name = :ONE_TIME_SELLING_MODEL_NAME AND Status = 'Active' LIMIT 1
        ];
        return models.isEmpty() ? null : models[0].Id;
    }
}