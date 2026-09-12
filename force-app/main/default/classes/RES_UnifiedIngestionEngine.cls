/**
 * Stage 2 of the product import pipeline: RES_Product_Staging__c -> Revenue Cloud object graph.
 */
public with sharing class RES_UnifiedIngestionEngine implements Database.Batchable<sObject>, Database.Stateful {

    private final String layoutCode;

    private Set<String> newProductCodes = new Set<String>();
    private Map<String, Id> catalogIdByCode  = new Map<String, Id>();
    private Map<String, Id> categoryIdByCode = new Map<String, Id>();
    private Map<String, Id> psmIdByKey       = new Map<String, Id>();
    private Boolean sellingModelsLoaded      = false;

    private List<Id> targetPricebookIds = new List<Id>();
    private Boolean pricebooksResolved  = false;

    private Map<String, Boolean> productActiveByCode = new Map<String, Boolean>();

    private Id classificationId;
    private Boolean classificationResolved = false;
    public Integer totalAttributes   = 0;
    public Integer totalMeasurements = 0;
    public Integer totalAdjustments  = 0;

    public Integer totalCatalogs          = 0;
    public Integer totalCategories        = 0;
    public Integer totalSellingModels     = 0;
    public Integer totalProducts          = 0;
    public Integer totalPricebookEntries  = 0;
    public Integer totalCategoryLinks     = 0;
    public Integer totalSellingModelLinks = 0;
    public Integer totalRowsCompleted     = 0;
    public Integer totalRowsErrored       = 0;
    public List<String> errorSamples      = new List<String>();

    private static final Integer MAX_ERROR_SAMPLES = 25;

    private static final String F_CODE            = 'RES_Product_Code__c';
    private static final String F_CATALOG_NAME    = 'RES_Catalog_Name__c';
    private static final String F_BUILDING_NAME   = 'RES_Building_Name__c';
    private static final String F_CATEGORY_NAME   = 'RES_Category_Name__c';
    private static final String F_CONDITION_TYPE  = 'RES_Condition_Type__c';
    private static final String F_CONDITION_PRICE = 'RES_Condition_Price__c';
    private static final String F_PRICE           = 'RES_Price__c';
    private static final String F_COND_VALID_FROM = 'RES_Condition_Valid_From__c';
    private static final String F_COND_VALID_TO   = 'RES_Condition_Valid_To__c';
    private static final String F_LAND            = 'RES_Land__c';
    private static final String F_PARAMETER_1     = 'RES_Parameter_1__c';

    public RES_UnifiedIngestionEngine(String layoutCode) {
        this.layoutCode = layoutCode;
    }

    public RES_UnifiedIngestionEngine() {
        List<RES_IngestionConfig.Layout> layouts = RES_IngestionConfig.activeLayouts();
        this.layoutCode = layouts.isEmpty() ? null : layouts[0].code;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return new RES_ProductStagingDAOLayer().getPendingStagingRecordsBatch();
    }

    public void execute(Database.BatchableContext bc, List<RES_Product_Staging__c> scope) {
        Map<Id, List<String>> rowErrors = new Map<Id, List<String>>();
        for (RES_Product_Staging__c stg : scope) {
            rowErrors.put(stg.Id, new List<String>());
        }

        productActiveByCode.clear();

        resolveCatalogs(scope, rowErrors);
        resolveCategories(scope, rowErrors);
        resolveSellingModels(scope, rowErrors);

        Map<String, Id> productIdByCode = upsertProducts(scope, rowErrors);

        linkProductsToCategories(scope, productIdByCode);
        disqualifyNewProducts(productIdByCode);
        linkProductsToSellingModels(scope, productIdByCode);
        syncPricebookEntries(scope, productIdByCode, rowErrors);
        syncProductAttributes(scope, productIdByCode, rowErrors);
        syncPricingOptions(scope, productIdByCode, rowErrors);
        syncMeasurements(scope, productIdByCode, rowErrors);

        finalizeStagingRows(scope, rowErrors);
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('=== PRODUCT IMPORT SUMMARY (' + layoutCode + ') ===');
        System.debug(' Catalogs created             : ' + totalCatalogs);
        System.debug(' Categories created          : ' + totalCategories);
        System.debug(' Selling models created      : ' + totalSellingModels);
        System.debug(' Products upserted           : ' + totalProducts);
        System.debug(' Category links created      : ' + totalCategoryLinks);
        System.debug(' Selling model links created : ' + totalSellingModelLinks);
        System.debug(' Pricebook entries synced    : ' + totalPricebookEntries);
        System.debug(' Product attributes synced   : ' + totalAttributes);
        System.debug(' Measurements synced         : ' + totalMeasurements);
        System.debug(' Price adjustments synced    : ' + totalAdjustments);
        System.debug(' Staging rows completed      : ' + totalRowsCompleted);
        System.debug(' Staging rows errored        : ' + totalRowsErrored);
        for (String e : errorSamples) System.debug(LoggingLevel.ERROR, ' ' + e);
    }

    private void resolveCatalogs(List<RES_Product_Staging__c> scope, Map<Id, List<String>> rowErrors) {
        Map<String, List<RES_Product_Staging__c>> rowsByCode = new Map<String, List<RES_Product_Staging__c>>();
        for (RES_Product_Staging__c stg : scope) {
            String code = catalogCode(stg);
            if (code == null || catalogIdByCode.containsKey(code)) continue;
            if (!rowsByCode.containsKey(code)) rowsByCode.put(code, new List<RES_Product_Staging__c>());
            rowsByCode.get(code).add(stg);
        }
        if (rowsByCode.isEmpty()) return;

        List<ProductCatalog> existingCatalogs = new RES_ProductCatalogDAOLayer().getCatalogsByCodes(rowsByCode.keySet());
        for (ProductCatalog existing : existingCatalogs) {
            catalogIdByCode.put(existing.Code, existing.Id);
            rowsByCode.remove(existing.Code);
        }
        if (rowsByCode.isEmpty()) return;

        List<ProductCatalog> toInsert = new List<ProductCatalog>();
        List<String> codes           = new List<String>();
        for (String code : rowsByCode.keySet()) {
            List<RES_Product_Staging__c> rows = rowsByCode.get(code);
            ProductCatalog pc = new ProductCatalog(
                Code = code,
                Name = truncate('Business Entity ' + textOf(rows[0], F_CATALOG_NAME), 255)
            );
            applyTargetMaps(pc, 'ProductCatalog', rows, true, rowErrors);
            toInsert.add(pc);
            codes.add(code);
        }

        List<Database.SaveResult> saves = Database.insert(toInsert, false);
        for (Integer i = 0; i < saves.size(); i++) {
            if (saves[i].isSuccess()) {
                catalogIdByCode.put(codes[i], saves[i].getId());
                totalCatalogs++;
            } else {
                String msg = 'ProductCatalog "' + codes[i] + '": ' + saves[i].getErrors()[0].getMessage();
                recordError(msg);
                for (RES_Product_Staging__c stg : rowsByCode.get(codes[i])) addRowError(rowErrors, stg.Id, msg);
            }
        }
    }

    private void resolveCategories(List<RES_Product_Staging__c> scope, Map<Id, List<String>> rowErrors) {
        Map<String, List<RES_Product_Staging__c>> rowsByCode = new Map<String, List<RES_Product_Staging__c>>();
        for (RES_Product_Staging__c stg : scope) {
            String code = categoryCode(stg);
            if (code == null || categoryIdByCode.containsKey(code)) continue;
            if (!rowsByCode.containsKey(code)) rowsByCode.put(code, new List<RES_Product_Staging__c>());
            rowsByCode.get(code).add(stg);
        }
        if (rowsByCode.isEmpty()) return;

        List<ProductCategory> existingCategories = new RES_ProductCategoryDAOLayer().getCategoriesByCodes(rowsByCode.keySet());
        for (ProductCategory existing : existingCategories) {
            categoryIdByCode.put(existing.Code, existing.Id);
            rowsByCode.remove(existing.Code);
        }
        if (rowsByCode.isEmpty()) return;

        List<ProductCategory> toInsert = new List<ProductCategory>();
        List<String> codes              = new List<String>();
        for (String code : rowsByCode.keySet()) {
            List<RES_Product_Staging__c> rows = rowsByCode.get(code);
            Id catalogId = catalogIdByCode.get(catalogCode(rows[0]));
            if (catalogId == null) continue;

            String kind  = categoryKind(rows[0]);
            String value = categoryValue(rows[0]);

            ProductCategory cat = new ProductCategory(
                Code           = code,
                Name           = truncate(kind + ' ' + value, 200),
                CatalogId      = catalogId,
                IsNavigational = true
            );
            applyTargetMaps(cat, 'ProductCategory', rows, true, rowErrors);
            toInsert.add(cat);
            codes.add(code);
        }
        if (toInsert.isEmpty()) return;

        List<Database.SaveResult> saves = Database.insert(toInsert, false);
        for (Integer i = 0; i < saves.size(); i++) {
            if (saves[i].isSuccess()) {
                categoryIdByCode.put(codes[i], saves[i].getId());
                totalCategories++;
            } else {
                String msg = 'ProductCategory "' + codes[i] + '": ' + saves[i].getErrors()[0].getMessage();
                recordError(msg);
                for (RES_Product_Staging__c stg : rowsByCode.get(codes[i])) addRowError(rowErrors, stg.Id, msg);
            }
        }
    }

    private void resolveSellingModels(List<RES_Product_Staging__c> scope, Map<Id, List<String>> rowErrors) {
        if (!sellingModelsLoaded) {
            List<ProductSellingModel> existingModels = new RES_ProductSellingModelDAOLayer().getAllSellingModels();
            for (ProductSellingModel psm : existingModels) {
                psmIdByKey.put(
                    sellingModelKey(psm.SellingModelType, psm.PricingTerm, psm.PricingTermUnit),
                    psm.Id
                );
            }
            sellingModelsLoaded = true;
        }

        Map<String, ProductSellingModel> toCreate = new Map<String, ProductSellingModel>();
        for (RES_Product_Staging__c stg : scope) {
            if (!isPricedRow(stg)) continue;
            SellingModelSpec spec = specForRow(stg);
            String key            = sellingModelKey(spec.sellingModelType, spec.pricingTerm, spec.pricingTermUnit);
            if (psmIdByKey.containsKey(key) || toCreate.containsKey(key)) continue;

            ProductSellingModel psm = new ProductSellingModel(
                Name             = truncate(spec.name, 255),
                SellingModelType = spec.sellingModelType
            );
            if (spec.sellingModelType != 'OneTime') {
                psm.PricingTerm     = spec.pricingTerm;
                psm.PricingTermUnit = spec.pricingTermUnit;
            }
            putSafePicklist(psm, 'Status', 'Active');
            toCreate.put(key, psm);
        }
        if (toCreate.isEmpty()) return;

        List<String> keys               = new List<String>(toCreate.keySet());
        List<ProductSellingModel> psms = new List<ProductSellingModel>();
        for (String k : keys) psms.add(toCreate.get(k));

        List<Database.SaveResult> saves = Database.insert(psms, false);
        for (Integer i = 0; i < saves.size(); i++) {
            if (saves[i].isSuccess()) {
                psmIdByKey.put(keys[i], saves[i].getId());
                totalSellingModels++;
            } else {
                recordError('ProductSellingModel "' + psms[i].Name + '": ' + saves[i].getErrors()[0].getMessage());
            }
        }
    }

    private Map<String, Id> upsertProducts(List<RES_Product_Staging__c> scope, Map<Id, List<String>> rowErrors) {
        Map<String, List<RES_Product_Staging__c>> rowsByCode = new Map<String, List<RES_Product_Staging__c>>();
        for (RES_Product_Staging__c stg : scope) {
            String code = textOf(stg, F_CODE);
            if (String.isBlank(code)) {
                addRowError(rowErrors, stg.Id, 'Product Code is blank');
                continue;
            }
            if (!rowsByCode.containsKey(code)) rowsByCode.put(code, new List<RES_Product_Staging__c>());
            rowsByCode.get(code).add(stg);
        }
        if (rowsByCode.isEmpty()) return new Map<String, Id>();

        List<String> codes = new List<String>(rowsByCode.keySet());

        Map<String, Product2> existingByExtId = new Map<String, Product2>();
        List<Product2> existingList = new RES_Product2DAOLayer().getProductsByExternalIds(new Set<String>(codes));
        for (Product2 existing : existingList) {
            existingByExtId.put(existing.RES_Product_External_ID__c, existing);
        }

        Id recordTypeId = productRecordTypeId();
        List<Product2> products = new List<Product2>();

        for (String code : codes) {
            List<RES_Product_Staging__c> rows = rowsByCode.get(code);
            Product2 existing         = existingByExtId.get(code);
            Boolean isNew             = existing == null;
            if (isNew) newProductCodes.add(code);

            Product2 p = new Product2(RES_Product_External_ID__c = truncate(code, 255));
            if (isNew && recordTypeId != null) p.RecordTypeId = recordTypeId;
            Id classId = resolveClassification();
            if (classId != null) p.BasedOnId = classId;

            applyTargetMaps(p, 'Product2', rows, isNew, rowErrors);

            for (RES_Product_Staging__c row : rows) {
                Id catalogId = catalogIdByCode.get(catalogCode(row));
                if (catalogId != null) { p.RES_Business_Entity__c = catalogId; break; }
            }
            for (RES_Product_Staging__c row : rows) {
                Id categoryId = categoryIdByCode.get(categoryCode(row));
                if (categoryId != null) { p.RES_Building__c = categoryId; break; }
            }

            Object activeOnRecord = p.get('IsActive');
            Boolean activeFlag = activeOnRecord != null
                ? (Boolean) activeOnRecord
                : (isNew ? true : existing.IsActive);
            productActiveByCode.put(code, activeFlag);

            products.add(p);
        }

        Map<String, Id> productIdByCode = new Map<String, Id>();

        List<Database.UpsertResult> saves =
            Database.upsert(products, Product2.Fields.RES_Product_External_ID__c, false);

        for (Integer i = 0; i < saves.size(); i++) {
            String code = codes[i];
            if (saves[i].isSuccess()) {
                productIdByCode.put(code, saves[i].getId());
                totalProducts++;
            } else {
                String msg = 'Product2 "' + code + '": ' + saves[i].getErrors()[0].getMessage();
                recordError(msg);
                for (RES_Product_Staging__c stg : rowsByCode.get(code)) addRowError(rowErrors, stg.Id, msg);
            }
        }
        return productIdByCode;
    }

    private Id productRecordTypeId() {
        RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(layoutCode);
        if (layout == null || String.isBlank(layout.productRecordType)) return null;
        Schema.RecordTypeInfo rt = Product2.SObjectType.getDescribe()
                                       .getRecordTypeInfosByDeveloperName()
                                       .get(layout.productRecordType);
        return (rt != null && rt.isAvailable()) ? rt.getRecordTypeId() : null;
    }

    @TestVisible
    private void disqualifyNewProducts(Map<String, Id> productIdByCode) {
        Set<Id> productIds = new Set<Id>();
        for (String code : newProductCodes) {
            Id productId = productIdByCode.get(code);
            if (productId != null) productIds.add(productId);
        }
        if (productIds.isEmpty()) return;

        List<ProductDisqualification> existing = new RES_ProductDisqualificationDAOLayer().getDisqualificationsByProductIds(productIds);
        for (ProductDisqualification pd : existing) {
            productIds.remove(pd.ProductId);
        }
        if (productIds.isEmpty()) return;

        Date today = Date.today();
        List<ProductDisqualification> toInsert = new List<ProductDisqualification>();
        for (Id productId : productIds) {
            toInsert.add(new ProductDisqualification(
                ProductId         = productId,
                EffectiveFromDate = today,
                EffectiveToDate   = today.addYears(3),
                RES_Unit_Status__c = 'Draft'));
        }
        for (Database.SaveResult sr : Database.insert(toInsert, false)) {
            if (!sr.isSuccess()) recordError('ProductDisqualification: ' + sr.getErrors()[0].getMessage());
        }
    }

    private void linkProductsToCategories(List<RES_Product_Staging__c> scope, Map<String, Id> productIdByCode) {
        Map<String, ProductCategoryProduct> wanted = new Map<String, ProductCategoryProduct>();
        for (RES_Product_Staging__c stg : scope) {
            Id productId  = productIdByCode.get(textOf(stg, F_CODE));
            Id categoryId = categoryIdByCode.get(categoryCode(stg));
            if (productId == null || categoryId == null) continue;
            wanted.put(productId + '|' + categoryId,
                new ProductCategoryProduct(ProductId = productId, ProductCategoryId = categoryId));
        }
        if (wanted.isEmpty()) return;

        Set<Id> productIds = new Set<Id>(productIdByCode.values());
        List<ProductCategoryProduct> existingList = new RES_ProductCategoryProductDAOLayer().getCategoryProductsByProductIds(productIds);
        for (ProductCategoryProduct existing : existingList) {
            wanted.remove(existing.ProductId + '|' + existing.ProductCategoryId);
        }
        if (wanted.isEmpty()) return;

        for (Database.SaveResult sr : Database.insert(wanted.values(), false)) {
            if (sr.isSuccess()) totalCategoryLinks++;
            else recordError('ProductCategoryProduct: ' + sr.getErrors()[0].getMessage());
        }
    }

    private void linkProductsToSellingModels(List<RES_Product_Staging__c> scope, Map<String, Id> productIdByCode) {
        Map<String, ProductSellingModelOption> wanted = new Map<String, ProductSellingModelOption>();
        for (RES_Product_Staging__c stg : scope) {
            if (!isPricedRow(stg)) continue;
            Id productId = productIdByCode.get(textOf(stg, F_CODE));
            Id psmId     = psmIdByKey.get(sellingModelKey(specForRow(stg)));
            if (productId == null || psmId == null) continue;
            wanted.put(productId + '|' + psmId,
                new ProductSellingModelOption(Product2Id = productId, ProductSellingModelId = psmId,
                                              IsDefault = true));
        }
        if (wanted.isEmpty()) return;

        Set<Id> productIds = new Set<Id>(productIdByCode.values());
        List<ProductSellingModelOption> existingList = new RES_ProductSellingModelOptionDAOLayer().getSellingModelOptionsByProductIds(productIds);
        for (ProductSellingModelOption existing : existingList) {
            wanted.remove(existing.Product2Id + '|' + existing.ProductSellingModelId);
        }
        if (wanted.isEmpty()) return;

        for (Database.SaveResult sr : Database.insert(wanted.values(), false)) {
            if (sr.isSuccess()) totalSellingModelLinks++;
            else recordError('ProductSellingModelOption: ' + sr.getErrors()[0].getMessage());
        }
    }

    private void syncPricebookEntries(
        List<RES_Product_Staging__c> scope,
        Map<String, Id> productIdByCode,
        Map<Id, List<String>> rowErrors
    ) {
        if (productIdByCode.isEmpty()) return;

        List<Id> targetPricebooks = resolveTargetPricebooks();
        if (targetPricebooks.isEmpty()) return;

        Boolean pbeHasSellingModel = hasField(PricebookEntry.SObjectType, 'ProductSellingModelId');

        Map<String, PriceIntent> intents = new Map<String, PriceIntent>();
        for (RES_Product_Staging__c stg : scope) {
            if (!isPricedRow(stg)) continue;
            String code  = textOf(stg, F_CODE);
            Id productId = productIdByCode.get(code);
            if (productId == null) continue;

            Decimal price = decimalOf(stg, F_CONDITION_PRICE);
            if (price == null) price = decimalOf(stg, F_PRICE);
            if (price == null) {
                addRowError(rowErrors, stg.Id, 'No Price or Condition Price on the row - no PricebookEntry created');
                continue;
            }
            price = basePriceFor(stg, price);

            Id psmId = psmIdByKey.get(sellingModelKey(specForRow(stg)));
            if (pbeHasSellingModel && psmId == null) {
                addRowError(rowErrors, stg.Id, 'Selling model could not be resolved - no PricebookEntry created');
                continue;
            }

            Boolean shouldBeActive = productActiveByCode.get(code) == true;

            String key           = productId + '|' + (pbeHasSellingModel ? String.valueOf(psmId) : null);
            PriceIntent existing = intents.get(key);
            Date validFrom       = dateOf(stg, F_COND_VALID_FROM);
            if (existing == null || isNewer(validFrom, existing.validFrom)) {
                intents.put(key, new PriceIntent(productId, psmId, price, validFrom, stg.Id, shouldBeActive));
            }
        }
        if (intents.isEmpty()) return;

        for (Id pricebookId : targetPricebooks) {
            applyPricing(pricebookId, intents, productIdByCode, pbeHasSellingModel, rowErrors);
        }
    }

    @TestVisible
    private List<Id> resolveTargetPricebooks() {
        if (pricebooksResolved) return targetPricebookIds;
        pricebooksResolved = true;

        if (Test.isRunningTest()) {
            targetPricebookIds.add(Test.getStandardPricebookId());
            return targetPricebookIds;
        }

        List<Pricebook2> std = new RES_Pricebook2DAOLayer().getStandardPricebook();
        if (std.isEmpty()) {
            recordError('No standard price book found; pricing was skipped.');
            return targetPricebookIds;
        }
        targetPricebookIds.add(std[0].Id);

        RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(layoutCode);
        String bookName = layout == null ? null : layout.pricebookName;
        if (String.isBlank(bookName)) return targetPricebookIds;

        List<Pricebook2> named = new RES_Pricebook2DAOLayer().getPricebookByName(bookName);
        if (named.isEmpty()) {
            recordError('Price book "' + bookName + '" named by layout ' + layoutCode +
                        ' does not exist; only the standard price book was written.');
        } else if (named[0].IsActive != true) {
            recordError('Price book "' + bookName + '" is inactive; only the standard price book was written.');
        } else {
            targetPricebookIds.add(named[0].Id);
        }
        return targetPricebookIds;
    }

    private void applyPricing(
        Id pricebookId,
        Map<String, PriceIntent> intents,
        Map<String, Id> productIdByCode,
        Boolean pbeHasSellingModel,
        Map<Id, List<String>> rowErrors
    ) {
        Set<Id> productIds = new Set<Id>(productIdByCode.values());

        Map<String, PricebookEntry> existingByKey = new Map<String, PricebookEntry>();
        List<PricebookEntry> existingEntries = new RES_PricebookEntryDAOLayer().getEntriesByBookAndProducts(
            pricebookId, productIds, pbeHasSellingModel
        );

        for (PricebookEntry pbe : existingEntries) {
            String psm = pbeHasSellingModel ? String.valueOf(pbe.get('ProductSellingModelId')) : null;
            existingByKey.put(pbe.Product2Id + '|' + psm, pbe);
        }

        List<PricebookEntry> toInsert = new List<PricebookEntry>();
        List<PricebookEntry> toUpdate = new List<PricebookEntry>();
        List<Id> insertRows           = new List<Id>();
        List<Id> updateRows           = new List<Id>();

        for (String key : intents.keySet()) {
            PriceIntent intent     = intents.get(key);
            PricebookEntry current = existingByKey.get(key);

            if (current == null) {
                PricebookEntry pbe = new PricebookEntry(
                    Pricebook2Id = pricebookId,
                    Product2Id   = intent.productId,
                    UnitPrice    = intent.price,
                    IsActive     = intent.isActive
                );
                if (pbeHasSellingModel && intent.sellingModelId != null) {
                    pbe.put('ProductSellingModelId', intent.sellingModelId);
                }
                toInsert.add(pbe);
                insertRows.add(intent.stagingId);
            } else if (current.UnitPrice != intent.price || current.IsActive != intent.isActive) {
                toUpdate.add(new PricebookEntry(
                    Id        = current.Id,
                    UnitPrice = intent.price,
                    IsActive  = intent.isActive
                ));
                updateRows.add(intent.stagingId);
            }
        }

        if (!toInsert.isEmpty()) {
            List<Database.SaveResult> saves = Database.insert(toInsert, false);
            for (Integer i = 0; i < saves.size(); i++) {
                if (saves[i].isSuccess()) {
                    totalPricebookEntries++;
                } else {
                    String msg = 'PricebookEntry: ' + saves[i].getErrors()[0].getMessage();
                    recordError(msg);
                    addRowError(rowErrors, insertRows[i], msg);
                }
            }
        }
        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saves = Database.update(toUpdate, false);
            for (Integer i = 0; i < saves.size(); i++) {
                if (saves[i].isSuccess()) {
                    totalPricebookEntries++;
                } else {
                    String msg = 'PricebookEntry update: ' + saves[i].getErrors()[0].getMessage();
                    recordError(msg);
                    addRowError(rowErrors, updateRows[i], msg);
                }
            }
        }
    }

    private void finalizeStagingRows(List<RES_Product_Staging__c> scope, Map<Id, List<String>> rowErrors) {
        for (RES_Product_Staging__c stg : scope) {
            List<String> errs = rowErrors.get(stg.Id);
            if (errs != null && !errs.isEmpty()) {
                stg.RES_Processing_Status__c = 'Error';
                stg.RES_Error_Log__c = truncate(String.join(errs, '\n'), 32768);
                totalRowsErrored++;
            } else {
                stg.RES_Processing_Status__c = 'Completed';
                stg.RES_Error_Log__c = null;
                totalRowsCompleted++;
            }
        }
        Database.update(scope, false);
    }

    private void applyTargetMaps(
        SObject rec,
        String objectName,
        List<RES_Product_Staging__c> rows,
        Boolean isNew,
        Map<Id, List<String>> rowErrors
    ) {
        Schema.SObjectType targetType = rec.getSObjectType();

        for (RES_IngestionConfig.TargetMap tm : RES_IngestionConfig.targetMapsFor(layoutCode, objectName)) {
            if (tm.valueKind == 'Child_Record') continue;
            if (!isNew && tm.skipOnUpdate) continue;

            Schema.SObjectField targetField = fieldToken(targetType, tm.targetField);
            if (targetField == null) {
                recordError('Mapping targets ' + objectName + '.' + tm.targetField + ', which does not exist.');
                continue;
            }

            if (tm.valueKind == 'Literal') {
                putLiteral(rec, targetField, tm.literalValue);
                continue;
            }

            if (String.isBlank(tm.stagingField)) {
                recordError('Mapping for ' + objectName + '.' + tm.targetField + ' has no staging field set.');
                continue;
            }

            Object value = merged(rows, tm.stagingField, tm.mergeStrategy);
            if (value == null) continue;

            if (tm.valueKind == 'Picklist_Safe') {
                String v = safePicklist(targetField, String.valueOf(value));
                if (v == null) {
                    String msg = tm.stagingField + ' "' + value + '" is not an active value on ' +
                                 objectName + '.' + tm.targetField + ' - left blank';
                    for (RES_Product_Staging__c stg : rows) addRowError(rowErrors, stg.Id, msg);
                    recordError(msg);
                } else {
                    rec.put(targetField, v);
                }

            } else if (tm.valueKind == 'Temporal') {
                putTemporal(rec, targetField, value);

            } else {
                putCoerced(rec, targetField, value);
            }
        }
    }

    @TestVisible
    private static Object merged(List<RES_Product_Staging__c> rows, String fieldApiName, String strategy) {
        Object found = null;
        for (RES_Product_Staging__c r : rows) {
            Object v;
            try {
                v = r.get(fieldApiName);
            } catch (Exception e) {
                return null;
            }
            if (v == null) continue;
            if (v instanceof String && String.isBlank((String) v)) continue;
            if (strategy == 'Last_Non_Null') found = v;
            else return v;
        }
        return found;
    }

    @TestVisible
    private static void putCoerced(SObject rec, Schema.SObjectField field, Object value) {
        Schema.DescribeFieldResult dfr = field.getDescribe();
        Schema.DisplayType t           = dfr.getType();

        if (t == Schema.DisplayType.DATE) {
            if (value instanceof Datetime) { rec.put(field, ((Datetime) value).date()); return; }
            rec.put(field, value); return;
        }
        if (t == Schema.DisplayType.DATETIME) {
            if (value instanceof Date) {
                rec.put(field, Datetime.newInstance((Date) value, Time.newInstance(0, 0, 0, 0))); return;
            }
            rec.put(field, value); return;
        }
        if (t == Schema.DisplayType.INTEGER || t == Schema.DisplayType.LONG) {
            if (value instanceof Decimal) {
                rec.put(field, Integer.valueOf(((Decimal) value).setScale(0, System.RoundingMode.HALF_UP)));
                return;
            }
            rec.put(field, value); return;
        }
        if (t == Schema.DisplayType.STRING || t == Schema.DisplayType.TEXTAREA) {
            Integer len = dfr.getLength();
            rec.put(field, len > 0 ? truncate(String.valueOf(value), len) : String.valueOf(value));
            return;
        }
        if (t == Schema.DisplayType.BOOLEAN) {
            if (value instanceof Boolean) { rec.put(field, value); return; }
            String flag = (value == null) ? '' : String.valueOf(value).trim().toUpperCase();
            if (String.isBlank(flag) || flag == 'FALSE' || flag == 'N' || flag == 'NO' || flag == '0') {
                rec.put(field, false);
            } else {
                rec.put(field, true);
            }
            return;
        }
        rec.put(field, value);
    }

    @TestVisible
    private static void putLiteral(SObject rec, Schema.SObjectField field, String literal) {
        if (literal == null) return;
        Schema.DisplayType t = field.getDescribe().getType();
        try {
            if (t == Schema.DisplayType.BOOLEAN) {
                rec.put(field, literal.trim().equalsIgnoreCase('true'));
            } else if (t == Schema.DisplayType.DOUBLE || t == Schema.DisplayType.CURRENCY
                       || t == Schema.DisplayType.PERCENT) {
                rec.put(field, Decimal.valueOf(literal.trim()));
            } else if (t == Schema.DisplayType.INTEGER || t == Schema.DisplayType.LONG) {
                rec.put(field, Integer.valueOf(literal.trim()));
            } else if (t == Schema.DisplayType.PICKLIST) {
                String v = safePicklist(field, literal);
                if (v != null) rec.put(field, v);
            } else {
                rec.put(field, literal);
            }
        } catch (Exception e) {
        }
    }

    @TestVisible
    private static void putTemporal(SObject rec, Schema.SObjectField field, Object value) {
        if (value == null) return;
        Datetime dt;
        if (value instanceof Datetime)  dt = (Datetime) value;
        else if (value instanceof Date) dt = Datetime.newInstance((Date) value, Time.newInstance(0, 0, 0, 0));
        else return;

        rec.put(field, field.getDescribe().getType() == Schema.DisplayType.DATE
                       ? (Object) dt.date() : (Object) dt);
    }

    public static String safePicklist(Schema.SObjectField field, String raw) {
        if (String.isBlank(raw) || field == null) return null;

        Schema.DescribeFieldResult dfr = field.getDescribe();
        Schema.DisplayType t           = dfr.getType();
        if (t != Schema.DisplayType.PICKLIST && t != Schema.DisplayType.MULTIPICKLIST) return raw;

        if (!picklistCache.containsKey(field)) {
            Map<String, String> accepted = new Map<String, String>();
            for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                if (!pe.isActive()) continue;
                accepted.put(pe.getValue().toLowerCase(), pe.getValue());
                if (String.isNotBlank(pe.getLabel())) accepted.put(pe.getLabel().toLowerCase(), pe.getValue());
            }
            picklistCache.put(field, accepted);
        }
        return picklistCache.get(field).get(raw.trim().toLowerCase());
    }

    private static Map<Schema.SObjectField, Map<String, String>> picklistCache =
        new Map<Schema.SObjectField, Map<String, String>>();

    private static void putSafePicklist(SObject rec, String fieldApiName, String raw) {
        Schema.SObjectField f = fieldToken(rec.getSObjectType(), fieldApiName);
        if (f == null) return;
        String value = safePicklist(f, raw);
        if (value != null) rec.put(f, value);
    }

    private static Schema.SObjectField fieldToken(Schema.SObjectType sobjType, String fieldApiName) {
        if (sobjType == null || String.isBlank(fieldApiName)) return null;
        return sobjType.getDescribe().fields.getMap().get(fieldApiName.toLowerCase());
    }

    private static Boolean hasField(Schema.SObjectType sobjType, String fieldApiName) {
        return fieldToken(sobjType, fieldApiName) != null;
    }

    private static String textOf(RES_Product_Staging__c stg, String fieldApiName) {
        Object v = stg.get(fieldApiName);
        return v == null ? null : String.valueOf(v);
    }

    private static Decimal decimalOf(RES_Product_Staging__c stg, String fieldApiName) {
        Object v = stg.get(fieldApiName);
        return v == null ? null : (Decimal) v;
    }

    private static Date dateOf(RES_Product_Staging__c stg, String fieldApiName) {
        Object v = stg.get(fieldApiName);
        if (v == null) return null;
        if (v instanceof Datetime) return ((Datetime) v).date();
        return (Date) v;
    }

    private static String categoryValue(RES_Product_Staging__c stg) {
        String b = textOf(stg, F_BUILDING_NAME);
        if (String.isNotBlank(b)) return b;
        String l = textOf(stg, F_LAND);
        if (String.isNotBlank(l)) return l;
        return textOf(stg, F_CATEGORY_NAME);
    }

    private static String categoryKind(RES_Product_Staging__c stg) {
        if (String.isNotBlank(textOf(stg, F_BUILDING_NAME))) return 'Building';
        if (String.isNotBlank(textOf(stg, F_LAND)))          return 'Land';
        return 'Building';
    }

    private static String catalogCode(RES_Product_Staging__c stg) {
        String be = textOf(stg, F_CATALOG_NAME);
        if (String.isBlank(be)) return null;
        return truncate('BE-' + be.trim(), 255);
    }

    private static String categoryCode(RES_Product_Staging__c stg) {
        String be    = textOf(stg, F_CATALOG_NAME);
        String value = categoryValue(stg);
        if (String.isBlank(be) || String.isBlank(value)) return null;
        String prefix = categoryKind(stg) == 'Land' ? 'LND-' : 'BLD-';
        return truncate(prefix + be.trim() + '-' + value.trim(), 255);
    }

    private static String sellingModelKey(String type, Integer term, String unit) {
        if (type == 'OneTime') return 'OneTime';
        return type + '|' + (term == null ? '' : String.valueOf(term)) + '|' + (unit == null ? '' : unit);
    }

    private static String sellingModelKey(String type, Decimal term, String unit) {
        return sellingModelKey(type, term == null ? null : Integer.valueOf(term), unit);
    }

    private static String sellingModelKey(SellingModelSpec spec) {
        return sellingModelKey(spec.sellingModelType, spec.pricingTerm, spec.pricingTermUnit);
    }

    private RES_IngestionConfig.ConditionMapping conditionFor(RES_Product_Staging__c stg) {
        return RES_IngestionConfig.conditionMapping(layoutCode, textOf(stg, F_CONDITION_TYPE));
    }

    private Boolean isPricedRow(RES_Product_Staging__c stg) {
        RES_IngestionConfig.ConditionMapping cm = conditionFor(stg);
        if (cm == null) return true;
        return cm.isPrimary == true || cm.handling == 'Pricebook_Entry';
    }

    private Decimal basePriceFor(RES_Product_Staging__c stg, Decimal rowPrice) {
        RES_IngestionConfig.ConditionMapping cm = conditionFor(stg);
        if (cm == null) return rowPrice;
        return cm.handling == 'Pricebook_Entry' ? rowPrice : 0;
    }

    private SellingModelSpec specForRow(RES_Product_Staging__c stg) {
        RES_IngestionConfig.ConditionMapping cm = conditionFor(stg);
        if (cm != null) {
            return new SellingModelSpec(
                'SAP ' + cm.conditionType, cm.sellingModelType, cm.pricingTerm, cm.pricingTermUnit);
        }
        return specForConditionTypeLegacy(stg);
    }

    private static SellingModelSpec specForConditionTypeLegacy(RES_Product_Staging__c stg) {
        String type = textOf(stg, 'RES_Selling_Model_Type__c');
        if (String.isNotBlank(type)) {
            String name    = textOf(stg, 'RES_Selling_Model_Name__c');
            Object term    = stg.get('RES_Pricing_Term__c');
            return new SellingModelSpec(
                String.isNotBlank(name) ? name : 'SAP Selling Model',
                type,
                term == null ? null : Integer.valueOf((Decimal) term),
                textOf(stg, 'RES_Pricing_Term_Unit__c')
            );
        }
        return specForConditionType(textOf(stg, F_CONDITION_TYPE));
    }

    public static SellingModelSpec specForConditionType(String conditionType) {
        String ct = String.isBlank(conditionType) ? '' : conditionType.trim().toUpperCase();

        if (ct == 'Y100') return new SellingModelSpec('SAP Y100 - Sale Price',     'OneTime',     null, null);
        if (ct == 'Y200') return new SellingModelSpec('SAP Y200 - Monthly Rent',   'TermDefined', 1,    'Months');
        if (ct == 'Y300') return new SellingModelSpec('SAP Y300 - Annual Rent',    'TermDefined', 1,    'Years');
        if (ct == 'Y400') return new SellingModelSpec('SAP Y400 - Service Charge', 'TermDefined', 1,    'Years');

        return new SellingModelSpec('SAP Default - One Time', 'OneTime', null, null);
    }

    public class SellingModelSpec {
        public String name;
        public String sellingModelType;
        public Integer pricingTerm;
        public String pricingTermUnit;

        public SellingModelSpec(String name, String sellingModelType, Integer pricingTerm, String pricingTermUnit) {
            this.name             = name;
            this.sellingModelType = sellingModelType;
            this.pricingTerm      = pricingTerm;
            this.pricingTermUnit  = pricingTermUnit;
        }
    }

    private class PriceIntent {
        Id productId;
        Id sellingModelId;
        Decimal price;
        Date validFrom;
        Id stagingId;
        Boolean isActive;

        PriceIntent(Id productId, Id sellingModelId, Decimal price,
                    Date validFrom, Id stagingId, Boolean isActive) {
            this.productId      = productId;
            this.sellingModelId = sellingModelId;
            this.price          = price;
            this.validFrom      = validFrom;
            this.stagingId      = stagingId;
            this.isActive       = isActive;
        }
    }

    private void syncProductAttributes(
        List<RES_Product_Staging__c> scope,
        Map<String, Id> productIdByCode,
        Map<Id, List<String>> rowErrors
    ) {
        Map<String, Decimal> valueByKey   = new Map<String, Decimal>();
        Map<String, Id> productByKey      = new Map<String, Id>();
        Map<String, String> typeByAttr    = new Map<String, String>();
        Map<String, Id> rowByKey          = new Map<String, Id>();

        for (RES_Product_Staging__c stg : scope) {
            RES_IngestionConfig.ConditionMapping cm = conditionFor(stg);
            if (cm == null || cm.handling != 'Product_Attribute') continue;
            if (String.isBlank(cm.attributeName)) {
                addRowError(rowErrors, stg.Id,
                    'Condition ' + cm.conditionType + ' is configured as a product attribute but names no attribute');
                continue;
            }
            Id productId = productIdByCode.get(textOf(stg, F_CODE));
            if (productId == null) continue;

            Decimal value = decimalOf(stg, F_CONDITION_PRICE);
            if (value == null) value = decimalOf(stg, F_PRICE);
            if (value == null) {
                addRowError(rowErrors, stg.Id,
                    'Condition ' + cm.conditionType + ' carries no price, so no attribute was written');
                continue;
            }

            String key = productId + '|' + cm.attributeName;
            valueByKey.put(key, value);
            productByKey.put(key, productId);
            typeByAttr.put(cm.attributeName, cm.attributeDataType);
            rowByKey.put(key, stg.Id);
        }
        addTargetMapAttributes(scope, productIdByCode, valueByKey, productByKey, typeByAttr, rowByKey);

        if (valueByKey.isEmpty()) return;

        Id classId = resolveClassification();
        if (classId == null) {
            recordError('No ProductClassification configured or found for layout ' + layoutCode +
                        '; condition attributes were skipped.');
            return;
        }

        Map<String, Id> attrIdByName    = ensureAttributeDefinitions(typeByAttr);
        Map<Id, Id> classAttrByAttrId   = ensureClassificationAttrs(classId, attrIdByName.values());

        Set<Id> productIds = new Set<Id>(productByKey.values());
        Set<Id> attrIds    = new Set<Id>(attrIdByName.values());
        Map<String, ProductAttributeDefinition> existing = new Map<String, ProductAttributeDefinition>();
        List<ProductAttributeDefinition> existingPads = new RES_ProductAttributeDefinitionDAOLayer().getAttributeDefinitionsByProductsAndAttrs(productIds, attrIds);
        for (ProductAttributeDefinition pad : existingPads) {
            existing.put(pad.Product2Id + '|' + pad.AttributeDefinitionId, pad);
        }

        List<ProductAttributeDefinition> toInsert = new List<ProductAttributeDefinition>();
        List<ProductAttributeDefinition> toUpdate = new List<ProductAttributeDefinition>();
        List<Id> insertRows = new List<Id>();

        for (String key : valueByKey.keySet()) {
            String attrName = key.substringAfter('|');
            Id productId    = productByKey.get(key);
            Id attrId       = attrIdByName.get(attrName);
            if (attrId == null) continue;

            String wanted   = String.valueOf(valueByKey.get(key));
            ProductAttributeDefinition current = existing.get(productId + '|' + attrId);

            if (current == null) {
                Id classAttrId = classAttrByAttrId.get(attrId);
                if (classAttrId == null) continue;
                toInsert.add(new ProductAttributeDefinition(
                    Name                             = truncate(attrName, 255),
                    Product2Id                       = productId,
                    AttributeDefinitionId            = attrId,
                    ProductClassificationAttributeId = classAttrId,
                    DefaultValue                     = wanted,
                    Sequence                         = 1
                ));
                insertRows.add(rowByKey.get(key));
            } else if (current.DefaultValue != wanted) {
                toUpdate.add(new ProductAttributeDefinition(Id = current.Id, DefaultValue = wanted));
            }
        }

        if (!toInsert.isEmpty()) {
            List<Database.SaveResult> saves = Database.insert(toInsert, false);
            for (Integer i = 0; i < saves.size(); i++) {
                if (saves[i].isSuccess()) {
                    totalAttributes++;
                } else {
                    String msg = 'ProductAttributeDefinition: ' + saves[i].getErrors()[0].getMessage();
                    recordError(msg);
                    addRowError(rowErrors, insertRows[i], msg);
                }
            }
        }
        if (!toUpdate.isEmpty()) {
            for (Database.SaveResult sr : Database.update(toUpdate, false)) {
                if (sr.isSuccess()) totalAttributes++;
                else recordError('ProductAttributeDefinition update: ' + sr.getErrors()[0].getMessage());
            }
        }
    }

    private void addTargetMapAttributes(
        List<RES_Product_Staging__c> scope,
        Map<String, Id> productIdByCode,
        Map<String, Decimal> valueByKey,
        Map<String, Id> productByKey,
        Map<String, String> typeByAttr,
        Map<String, Id> rowByKey
    ) {
        List<RES_IngestionConfig.TargetMap> attrMaps = new List<RES_IngestionConfig.TargetMap>();
        Map<String, RES_IngestionConfig.TargetMap> measureByCode =
            new Map<String, RES_IngestionConfig.TargetMap>();

        for (RES_IngestionConfig.TargetMap tm : RES_IngestionConfig.targetMaps(layoutCode)) {
            if (tm.valueKind == 'Product_Attribute' || tm.valueKind == 'Product_Attribute_Computed') {
                if (String.isNotBlank(tm.attributeName)) attrMaps.add(tm);
            }
            if (tm.valueKind == 'Child_Record' && String.isNotBlank(tm.sourceCode)) {
                measureByCode.put(tm.sourceCode.trim().toUpperCase(), tm);
            }
        }
        if (attrMaps.isEmpty()) return;

        Map<String, List<RES_Product_Staging__c>> rowsByCode = new Map<String, List<RES_Product_Staging__c>>();
        for (RES_Product_Staging__c stg : scope) {
            String code = textOf(stg, F_CODE);
            if (String.isBlank(code)) continue;
            if (!rowsByCode.containsKey(code)) rowsByCode.put(code, new List<RES_Product_Staging__c>());
            rowsByCode.get(code).add(stg);
        }

        for (String code : rowsByCode.keySet()) {
            Id productId = productIdByCode.get(code);
            if (productId == null) continue;
            List<RES_Product_Staging__c> rows = rowsByCode.get(code);

            for (RES_IngestionConfig.TargetMap tm : attrMaps) {
                Object raw = merged(rows, tm.stagingField, tm.mergeStrategy);
                if (raw == null) continue;
                Decimal base;
                try { base = (Decimal) raw; } catch (Exception e) { continue; }

                Decimal value = base;
                if (tm.valueKind == 'Product_Attribute_Computed') {
                    Object p1 = merged(rows, F_PARAMETER_1, 'First_Non_Null');
                    if (p1 == null) continue;
                    RES_IngestionConfig.TargetMap measure =
                        measureByCode.get(String.valueOf(p1).trim().toUpperCase());
                    if (measure == null) {
                        recordError('Parameter-1 "' + p1 + '" does not match any mapped measurement, ' +
                                    'so ' + tm.attributeName + ' could not be computed for ' + code);
                        continue;
                    }
                    Object area = merged(rows, measure.stagingField, 'First_Non_Null');
                    if (area == null) continue;
                    value = base * ((Decimal) area);
                }

                String key = productId + '|' + tm.attributeName;
                valueByKey.put(key, value.setScale(2, System.RoundingMode.HALF_UP));
                productByKey.put(key, productId);
                typeByAttr.put(tm.attributeName, 'Currency');
                rowByKey.put(key, rows[0].Id);
            }
        }
    }

    private Id resolveClassification() {
        if (classificationResolved) return classificationId;
        classificationResolved = true;

        RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(layoutCode);
        if (layout == null || String.isBlank(layout.productClassification)) return null;

        String name = layout.productClassification;
        List<ProductClassification> found = new RES_ProductClassificationDAOLayer().getClassificationByName(name);
        if (found.isEmpty()) {
            recordError('ProductClassification "' + name + '" does not exist.');
        } else {
            classificationId = found[0].Id;
        }
        return classificationId;
    }

    private Map<String, Id> ensureAttributeDefinitions(Map<String, String> dataTypeByName) {
        Map<String, Id> byName = new Map<String, Id>();
        Set<String> names = dataTypeByName.keySet();
        List<AttributeDefinition> existingDefs = new RES_AttributeDefinitionDAOLayer().getAttributeDefinitionsByNames(names);
        for (AttributeDefinition ad : existingDefs) {
            byName.put(ad.Name, ad.Id);
        }

        List<AttributeDefinition> toCreate = new List<AttributeDefinition>();
        List<String> created = new List<String>();
        for (String name : names) {
            if (byName.containsKey(name)) continue;
            toCreate.add(new AttributeDefinition(
                Name          = truncate(name, 255),
                Label         = truncate(name, 255),
                DeveloperName = truncate(name.replaceAll('[^a-zA-Z0-9]', '_'), 80),
                DataType      = dataTypeByName.get(name),
                IsActive      = true
            ));
            created.add(name);
        }
        if (!toCreate.isEmpty()) {
            List<Database.SaveResult> saves = Database.insert(toCreate, false);
            for (Integer i = 0; i < saves.size(); i++) {
                if (saves[i].isSuccess()) byName.put(created[i], saves[i].getId());
                else recordError('AttributeDefinition "' + created[i] + '": ' + saves[i].getErrors()[0].getMessage());
            }
        }
        return byName;
    }

    private Map<Id, Id> ensureClassificationAttrs(Id classId, List<Id> attributeIds) {
        Map<Id, Id> byAttrId = new Map<Id, Id>();
        Set<Id> attrIds = new Set<Id>(attributeIds);
        List<ProductClassificationAttr> existingPcas = new RES_ProductClassificationAttrDAOLayer().getClassAttrsByClassAndAttrs(classId, attrIds);
        for (ProductClassificationAttr pca : existingPcas) {
            byAttrId.put(pca.AttributeDefinitionId, pca.Id);
        }

        List<ProductClassificationAttr> toCreate = new List<ProductClassificationAttr>();
        List<Id> created = new List<Id>();
        Map<Id, String> nameById = new Map<Id, String>();
        List<AttributeDefinition> attrDefs = new RES_AttributeDefinitionDAOLayer().getAttributeDefinitionsByIds(attrIds);
        for (AttributeDefinition ad : attrDefs) {
            nameById.put(ad.Id, ad.Name);
        }
        for (Id attrId : attrIds) {
            if (byAttrId.containsKey(attrId)) continue;
            toCreate.add(new ProductClassificationAttr(
                Name                    = truncate(nameById.get(attrId), 255),
                ProductClassificationId = classId,
                AttributeDefinitionId   = attrId
            ));
            created.add(attrId);
        }
        if (!toCreate.isEmpty()) {
            List<Database.SaveResult> saves = Database.insert(toCreate, false);
            for (Integer i = 0; i < saves.size(); i++) {
                if (saves[i].isSuccess()) byAttrId.put(created[i], saves[i].getId());
                else recordError('ProductClassificationAttr: ' + saves[i].getErrors()[0].getMessage());
            }
        }
        return byAttrId;
    }

    private void syncPricingOptions(
        List<RES_Product_Staging__c> scope,
        Map<String, Id> productIdByCode,
        Map<Id, List<String>> rowErrors
    ) {
        RES_IngestionConfig.Layout layout = RES_IngestionConfig.layoutByCode(layoutCode);
        if (layout == null || String.isBlank(layout.selectorAttribute)) return;

        Map<String, Map<String, OptionPrice>> priceByCodeAndSelector =
            new Map<String, Map<String, OptionPrice>>();
        Map<String, RES_IngestionConfig.ConditionMapping> mappingBySelector =
            new Map<String, RES_IngestionConfig.ConditionMapping>();
        Map<String, Id> rowIdByCodeAndSelector = new Map<String, Id>();
        String defaultSelector;

        for (RES_IngestionConfig.ConditionMapping cm : RES_IngestionConfig.conditionMappings(layoutCode).values()) {
            if (cm.isPrimary && String.isNotBlank(cm.selectorValue)) defaultSelector = cm.selectorValue;
        }

        for (RES_Product_Staging__c stg : scope) {
            RES_IngestionConfig.ConditionMapping cm = conditionFor(stg);
            if (cm == null || cm.handling != 'Attribute_Based_Adjustment') continue;
            if (String.isBlank(cm.selectorValue)) {
                addRowError(rowErrors, stg.Id, 'Condition ' + cm.conditionType +
                    ' is configured as an adjustment but names no selector value');
                continue;
            }
            String code  = textOf(stg, F_CODE);
            Id productId = productIdByCode.get(code);
            if (productId == null) continue;

            Decimal price = decimalOf(stg, F_CONDITION_PRICE);
            if (price == null) price = decimalOf(stg, F_PRICE);
            if (price == null) {
                addRowError(rowErrors, stg.Id, 'Condition ' + cm.conditionType +
                    ' carries no price, so no adjustment was created');
                continue;
            }
            if (!priceByCodeAndSelector.containsKey(code)) {
                priceByCodeAndSelector.put(code, new Map<String, OptionPrice>());
            }
            priceByCodeAndSelector.get(code).put(cm.selectorValue, new OptionPrice(
                price, dateOf(stg, F_COND_VALID_FROM), dateOf(stg, F_COND_VALID_TO)));
            mappingBySelector.put(cm.selectorValue, cm);
            rowIdByCodeAndSelector.put(code + '|' + cm.selectorValue, stg.Id);
        }
        if (priceByCodeAndSelector.isEmpty()) return;

        Id classId = resolveClassification();
        if (classId == null) {
            recordError('No ProductClassification for layout ' + layoutCode + '; pricing options skipped.');
            return;
        }
        Id scheduleId = resolveAdjustmentSchedule(layout);
        if (scheduleId == null) return;

        Id selectorAttrId = ensureSelectorAttribute(layout, mappingBySelector.keySet(), defaultSelector);
        if (selectorAttrId == null) return;

        Map<Id, Id> classAttrByAttrId = ensureClassificationAttrs(classId, new List<Id>{ selectorAttrId });
        Id classAttrId = classAttrByAttrId.get(selectorAttrId);
        if (classAttrId == null) return;

        Set<Id> productIds = new Set<Id>();
        for (String code : priceByCodeAndSelector.keySet()) productIds.add(productIdByCode.get(code));

        ensureSelectorOnProducts(productIds, selectorAttrId, classAttrId, layout, defaultSelector);

        Map<String, AttributeBasedAdjRule> ruleByKey = new Map<String, AttributeBasedAdjRule>();
        Set<String> wantedRuleNames = new Set<String>();
        Map<String, String> keyByRuleName = new Map<String, String>();
        for (String code : priceByCodeAndSelector.keySet()) {
            for (String sel : priceByCodeAndSelector.get(code).keySet()) {
                String name = truncate(code + ' :: ' + sel, 255);
                wantedRuleNames.add(name);
                keyByRuleName.put(name, code + '|' + sel);
            }
        }

        List<AttributeBasedAdjRule> existingRules = new RES_AttributeBasedAdjRuleDAOLayer().getRulesByNames(wantedRuleNames);
        for (AttributeBasedAdjRule r : existingRules) {
            ruleByKey.put(keyByRuleName.get(r.Name), r);
        }

        List<AttributeBasedAdjRule> newRules = new List<AttributeBasedAdjRule>();
        List<String> newRuleKeys = new List<String>();
        for (String name : wantedRuleNames) {
            String key = keyByRuleName.get(name);
            if (ruleByKey.containsKey(key)) continue;
            newRules.add(new AttributeBasedAdjRule(Name = name));
            newRuleKeys.add(key);
        }
        if (!newRules.isEmpty()) {
            List<Database.SaveResult> saves = Database.insert(newRules, false);
            for (Integer i = 0; i < saves.size(); i++) {
                if (saves[i].isSuccess()) {
                    ruleByKey.put(newRuleKeys[i], new AttributeBasedAdjRule(Id = saves[i].getId()));
                } else {
                    recordError('AttributeBasedAdjRule "' + newRules[i].Name + '": ' + saves[i].getErrors()[0].getMessage());
                }
            }
        }

        Set<Id> ruleIds = new Set<Id>();
        for (AttributeBasedAdjRule r : ruleByKey.values()) ruleIds.add(r.Id);
        Set<Id> rulesWithCondition = new Set<Id>();
        List<AttributeAdjustmentCondition> existingConds = new RES_AttributeAdjustmentConditionDAOLayer().getConditionsByRuleIds(ruleIds);
        for (AttributeAdjustmentCondition c : existingConds) {
            rulesWithCondition.add(c.AttributeBasedAdjRuleId);
        }

        List<AttributeAdjustmentCondition> newConds = new List<AttributeAdjustmentCondition>();
        for (String code : priceByCodeAndSelector.keySet()) {
            Id productId = productIdByCode.get(code);
            for (String sel : priceByCodeAndSelector.get(code).keySet()) {
                AttributeBasedAdjRule r = ruleByKey.get(code + '|' + sel);
                if (r == null || rulesWithCondition.contains(r.Id)) continue;
                newConds.add(new AttributeAdjustmentCondition(
                    AttributeBasedAdjRuleId = r.Id, AttributeDefinitionId = selectorAttrId,
                    ProductId = productId, Operator = 'equals', StringValue = sel));
            }
        }
        if (!newConds.isEmpty()) {
            for (Database.SaveResult sr : Database.insert(newConds, false)) {
                if (!sr.isSuccess()) recordError('AttributeAdjustmentCondition: ' + sr.getErrors()[0].getMessage());
            }
        }

        PriceAdjustmentSchedule sch = new RES_PriceAdjustmentScheduleDAOLayer().getScheduleById(scheduleId);
        Map<Id, AttributeBasedAdjustment> existingByRule = new Map<Id, AttributeBasedAdjustment>();
        List<AttributeBasedAdjustment> existingAdjs = new RES_AttributeBasedAdjustmentDAOLayer().getAdjustmentsByRuleIds(ruleIds);
        for (AttributeBasedAdjustment a : existingAdjs) {
            existingByRule.put(a.AttributeBasedAdjRuleId, a);
        }

        Id psmId = psmIdByKey.get('OneTime');
        List<AttributeBasedAdjustment> toInsert = new List<AttributeBasedAdjustment>();
        List<AttributeBasedAdjustment> toUpdate = new List<AttributeBasedAdjustment>();

        for (String code : priceByCodeAndSelector.keySet()) {
            Id productId = productIdByCode.get(code);
            Map<String, OptionPrice> bySel = priceByCodeAndSelector.get(code);
            for (String sel : bySel.keySet()) {
                AttributeBasedAdjRule r = ruleByKey.get(code + '|' + sel);
                if (r == null) continue;
                OptionPrice op = bySel.get(sel);
                RES_IngestionConfig.ConditionMapping cm = mappingBySelector.get(sel);
                AttributeBasedAdjustment current = existingByRule.get(r.Id);
                Datetime startsAt = adjustmentFrom(op.validFrom, sch);
                Datetime thru = adjustmentTo(op.validTo, sch);

                if (current == null) {
                    AttributeBasedAdjustment a = new AttributeBasedAdjustment(
                        PriceAdjustmentScheduleId = sch.Id,
                        AttributeBasedAdjRuleId   = r.Id,
                        ProductId                 = productId,
                        AdjustmentType            = cm == null ? 'Override' : cm.adjustmentType,
                        AdjustmentValue           = op.price,
                        EffectiveFrom              = startsAt,
                        EffectiveTo                = thru);
                    if (psmId != null) a.ProductSellingModelId = psmId;
                    toInsert.add(a);
                } else if (current.AdjustmentValue != op.price
                        || current.EffectiveFrom != startsAt
                        || current.EffectiveTo != thru) {
                    toUpdate.add(new AttributeBasedAdjustment(
                        Id              = current.Id,
                        AdjustmentValue = op.price,
                        EffectiveFrom   = startsAt,
                        EffectiveTo     = thru
                    ));
                }
            }
        }

        if (!toInsert.isEmpty()) {
            for (Database.SaveResult sr : Database.insert(toInsert, false)) {
                if (sr.isSuccess()) totalAdjustments++;
                else recordError('AttributeBasedAdjustment: ' + sr.getErrors()[0].getMessage());
            }
        }
        if (!toUpdate.isEmpty()) {
            for (Database.SaveResult sr : Database.update(toUpdate, false)) {
                if (sr.isSuccess()) totalAdjustments++;
                else recordError('AttributeBasedAdjustment update: ' + sr.getErrors()[0].getMessage());
            }
        }
    }

    @TestVisible
    private class OptionPrice {
        @TestVisible final Decimal price;
        final Date validFrom;
        final Date validTo;
        @TestVisible OptionPrice(Decimal price, Date validFrom, Date validTo) {
            this.price     = price;
            this.validFrom = validFrom;
            this.validTo   = validTo;
        }
    }

    @TestVisible
    private static Datetime adjustmentFrom(Date rowFrom, PriceAdjustmentSchedule sch) {
        Datetime earliest = sch.EffectiveFrom.addDays(1);
        if (rowFrom == null) return earliest;
        Datetime wanted = Datetime.newInstanceGmt(rowFrom, Time.newInstance(0, 0, 0, 0));
        return wanted < earliest ? earliest : wanted;
    }

    @TestVisible
    private static Datetime adjustmentTo(Date rowTo, PriceAdjustmentSchedule sch) {
        Datetime latest = sch.EffectiveTo == null ? null : sch.EffectiveTo.addDays(-1);
        if (rowTo == null) return latest;
        Datetime wanted = Datetime.newInstanceGmt(rowTo, Time.newInstance(23, 59, 59, 0));
        return (latest != null && wanted > latest) ? latest : wanted;
    }

    @TestVisible
    private Id resolveAdjustmentSchedule(RES_IngestionConfig.Layout layout) {
        if (String.isBlank(layout.priceAdjustmentSchedule)) {
            recordError('Layout ' + layoutCode + ' names no price adjustment schedule.');
            return null;
        }
        String name = layout.priceAdjustmentSchedule;
        List<PriceAdjustmentSchedule> found = new RES_PriceAdjustmentScheduleDAOLayer().getActiveScheduleByName(name);
        if (found.isEmpty()) {
            recordError('Price adjustment schedule "' + name + '" not found or inactive.');
            return null;
        }
        return found[0].Id;
    }

    @TestVisible
    private Id ensureSelectorAttribute(
        RES_IngestionConfig.Layout layout,
        Set<String> selectorValues,
        String defaultSelector
    ) {
        String attrName = layout.selectorAttribute;

        List<AttributeDefinition> existing = new RES_AttributeDefinitionDAOLayer().getAttributeDefinitionByName(attrName);
        Id picklistId;
        Id attrId;

        if (!existing.isEmpty()) {
            attrId = existing[0].Id;
            picklistId = existing[0].PicklistId;
        } else {
            AttributePicklist pl = new AttributePicklist(Name = attrName, DataType = 'Text', Status = 'Active');
            Database.SaveResult rp = Database.insert(pl, false);
            if (!rp.isSuccess()) {
                recordError('AttributePicklist "' + attrName + '": ' + rp.getErrors()[0].getMessage());
                return null;
            }
            picklistId = rp.getId();
            AttributeDefinition ad = new AttributeDefinition(
                Name = attrName, Label = attrName,
                DeveloperName = truncate(attrName.replaceAll('[^a-zA-Z0-9]', '_'), 80),
                DataType = 'Picklist', PicklistId = picklistId, IsActive = true);
            Database.SaveResult ra = Database.insert(ad, false);
            if (!ra.isSuccess()) {
                recordError('AttributeDefinition "' + attrName + '": ' + ra.getErrors()[0].getMessage());
                return null;
            }
            attrId = ra.getId();
        }

        if (picklistId != null) {
            Set<String> have = new Set<String>();
            List<AttributePicklistValue> existingValues = new RES_AttributePicklistValueDAOLayer().getValuesByPicklistId(picklistId);
            for (AttributePicklistValue v : existingValues) {
                have.add(v.Value);
            }
            List<AttributePicklistValue> toAdd = new List<AttributePicklistValue>();
            Integer seq = have.size() + 1;
            for (String sel : selectorValues) {
                if (have.contains(sel)) continue;
                toAdd.add(new AttributePicklistValue(
                    Name = sel, Code = sel.replaceAll('[^a-zA-Z0-9]', '_'), Value = sel,
                    DisplayValue = sel, PicklistId = picklistId, Status = 'Active',
                    Sequence = seq++, IsDefault = (sel == defaultSelector)));
            }
            if (!toAdd.isEmpty()) {
                for (Database.SaveResult sr : Database.insert(toAdd, false)) {
                    if (!sr.isSuccess()) recordError('AttributePicklistValue: ' + sr.getErrors()[0].getMessage());
                }
            }
        }

        if (String.isNotBlank(layout.attributeCategory)) selectorCategoryId = ensureCategory(layout.attributeCategory, attrId);
        return attrId;
    }

    private Id selectorCategoryId;

    @TestVisible
    private Id ensureCategory(String name, Id attrId) {
        List<AttributeCategory> cx = new RES_AttributeCategoryDAOLayer().getCategoryByName(name);
        Id catId;
        if (cx.isEmpty()) {
            Database.SaveResult r = Database.insert(new AttributeCategory(
                Name = name, Code = name.replaceAll('[^a-zA-Z0-9]', '_')), false);
            if (!r.isSuccess()) { recordError('AttributeCategory "' + name + '": ' + r.getErrors()[0].getMessage()); return null; }
            catId = r.getId();
        } else { catId = cx[0].Id; }

        if (new RES_AttributeCategoryAttributeDAOLayer().getCategoryAttributeCount(catId, attrId) == 0) {
            Database.SaveResult r = Database.insert(new AttributeCategoryAttribute(
                AttributeCategoryId = catId, AttributeDefinitionId = attrId), false);
            if (!r.isSuccess()) recordError('AttributeCategoryAttribute: ' + r.getErrors()[0].getMessage());
        }
        return catId;
    }

    @TestVisible
    private void ensureSelectorOnProducts(
        Set<Id> productIds,
        Id selectorAttrId,
        Id classAttrId,
        RES_IngestionConfig.Layout layout,
        String defaultSelector
    ) {
        Set<Id> have = new Set<Id>();
        List<ProductAttributeDefinition> existingPads = new RES_ProductAttributeDefinitionDAOLayer().getProductAttributeDefinitionsByAttrId(productIds, selectorAttrId);
        for (ProductAttributeDefinition p : existingPads) {
            have.add(p.Product2Id);
        }
        List<ProductAttributeDefinition> toAdd = new List<ProductAttributeDefinition>();
        for (Id pid : productIds) {
            if (pid == null || have.contains(pid)) continue;
            ProductAttributeDefinition pad = new ProductAttributeDefinition(
                Name = truncate(layout.selectorAttribute, 255),
                Product2Id = pid, AttributeDefinitionId = selectorAttrId,
                ProductClassificationAttributeId = classAttrId,
                DefaultValue = defaultSelector, Sequence = 1, IsPriceImpacting = true);
            if (selectorCategoryId != null) pad.AttributeCategoryId = selectorCategoryId;
            toAdd.add(pad);
        }
        if (toAdd.isEmpty()) return;
        for (Database.SaveResult sr : Database.insert(toAdd, false)) {
            if (!sr.isSuccess()) recordError('Selector ProductAttributeDefinition: ' + sr.getErrors()[0].getMessage());
        }
    }

    private void syncMeasurements(
        List<RES_Product_Staging__c> scope,
        Map<String, Id> productIdByCode,
        Map<Id, List<String>> rowErrors
    ) {
        List<RES_IngestionConfig.TargetMap> maps = new List<RES_IngestionConfig.TargetMap>();
        for (RES_IngestionConfig.TargetMap tm : RES_IngestionConfig.targetMaps(layoutCode)) {
            if (tm.valueKind == 'Child_Record' && 'RES_Measurement__c'.equalsIgnoreCase(tm.targetObject)) {
                maps.add(tm);
            }
        }
        if (maps.isEmpty() || productIdByCode.isEmpty()) return;

        Map<String, List<RES_Product_Staging__c>> rowsByCode = new Map<String, List<RES_Product_Staging__c>>();
        for (RES_Product_Staging__c stg : scope) {
            String code = textOf(stg, F_CODE);
            if (String.isBlank(code)) continue;
            if (!rowsByCode.containsKey(code)) rowsByCode.put(code, new List<RES_Product_Staging__c>());
            rowsByCode.get(code).add(stg);
        }

        Map<String, RES_Measurement__c> wanted = new Map<String, RES_Measurement__c>();
        for (String code : rowsByCode.keySet()) {
            Id productId = productIdByCode.get(code);
            if (productId == null) continue;
            List<RES_Product_Staging__c> rows = rowsByCode.get(code);
            RES_Product_Staging__c primary    = rows[0];

            Date validFrom = dateOf(primary, 'RES_Measurement_From__c');
            Date validTo   = dateOf(primary, 'RES_Measurement_To__c');
            Id catalogId   = catalogIdByCode.get(catalogCode(primary));
            Id categoryId  = categoryIdByCode.get(categoryCode(primary));

            for (RES_IngestionConfig.TargetMap tm : maps) {
                Object raw = merged(rows, tm.stagingField, tm.mergeStrategy);
                if (raw == null) continue;
                Decimal amount;
                try {
                    amount = (Decimal) raw;
                } catch (Exception e) {
                    continue;
                }
                RES_Measurement__c m = new RES_Measurement__c(
                    RES_Product__c             = productId,
                    RES_Measurement_Type__c   = tm.measurementType,
                    RES_Measurement_Amount__c = amount,
                    RES_Measurement_From__c   = validFrom,
                    RES_Measurement_To__c     = validTo
                );
                putSafePicklist(m, 'RES_Unit_Of_Measurement__c', tm.unitOfMeasurement);
                if (catalogId  != null) m.RES_Catalog__c  = catalogId;
                if (categoryId != null) m.RES_Category__c = categoryId;
                m.Name = truncate(code + ' ' + tm.measurementType, 80);
                wanted.put(productId + '|' + tm.measurementType, m);
            }
        }
        if (wanted.isEmpty()) return;

        Set<Id> productIds = new Set<Id>(productIdByCode.values());
        Map<String, RES_Measurement__c> existing = new Map<String, RES_Measurement__c>();
        List<RES_Measurement__c> existingMeasurements = new RES_MeasurementDAOLayer().getMeasurementsByProductIds(productIds);
        for (RES_Measurement__c m : existingMeasurements) {
            existing.put(m.RES_Product__c + '|' + m.RES_Measurement_Type__c, m);
        }

        List<RES_Measurement__c> toInsert = new List<RES_Measurement__c>();
        List<RES_Measurement__c> toUpdate = new List<RES_Measurement__c>();
        for (String key : wanted.keySet()) {
            RES_Measurement__c desired = wanted.get(key);
            RES_Measurement__c current = existing.get(key);
            if (current == null) {
                toInsert.add(desired);
            } else if (current.RES_Measurement_Amount__c != desired.RES_Measurement_Amount__c) {
                toUpdate.add(new RES_Measurement__c(
                    Id                         = current.Id,
                    RES_Measurement_Amount__c = desired.RES_Measurement_Amount__c
                ));
            }
        }

        if (!toInsert.isEmpty()) {
            for (Database.SaveResult sr : Database.insert(toInsert, false)) {
                if (sr.isSuccess()) totalMeasurements++;
                else recordError('RES_Measurement__c: ' + sr.getErrors()[0].getMessage());
            }
        }
        if (!toUpdate.isEmpty()) {
            for (Database.SaveResult sr : Database.update(toUpdate, false)) {
                if (sr.isSuccess()) totalMeasurements++;
                else recordError('RES_Measurement__c update: ' + sr.getErrors()[0].getMessage());
            }
        }
    }

    @TestVisible
    private static Boolean isNewer(Date candidate, Date current) {
        if (candidate == null) return false;
        if (current == null) return true;
        return candidate > current;
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || maxLength == null || value.length() <= maxLength) return value;
        return value.substring(0, maxLength);
    }

    private void addRowError(Map<Id, List<String>> rowErrors, Id stagingId, String message) {
        if (stagingId == null) return;
        if (!rowErrors.containsKey(stagingId)) rowErrors.put(stagingId, new List<String>());
        List<String> errs = rowErrors.get(stagingId);
        if (!errs.contains(message)) errs.add(message);
    }

    private void recordError(String message) {
        if (errorSamples.size() < MAX_ERROR_SAMPLES && !errorSamples.contains(message)) {
            errorSamples.add(message);
        }
        System.debug(LoggingLevel.ERROR, message);
    }
}