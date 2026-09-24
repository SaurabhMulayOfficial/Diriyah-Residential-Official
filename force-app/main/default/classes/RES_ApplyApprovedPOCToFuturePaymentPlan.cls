/**
* @ Class Name     	: RES_ApplyApprovedPOCToFuturePaymentPlan
* @ Description    	: Invoked (via RES_POC_After_Update_Flow) when a Project Completion Report's
*                       approval status becomes Approved. Clones every catalog-level Payment Plan
*                       (and its Installments) into a new version reflecting the approved POC%:
*                       each Installment's RES_POC_Percentage__c is the cumulative completion
*                       milestone it falls due at (e.g. 20/40/70/100), so installments whose own
*                       milestone is already below the approved POC% have come due and are merged
*                       into a single installment (its payment share is the sum of theirs); every
*                       installment whose milestone the approval hasn't reached yet is carried over
*                       unchanged. The new version is linked to its Installments via
*                       ProductRelatedComponent exactly like the original, and every Unit already
*                       wired to the previous version is repointed at the new one.
* @ Author			: Nikhil Takawale
*/
public with sharing class RES_ApplyApprovedPOCToFuturePaymentPlan {

    private static final String BUNDLE_COMPONENT_RELATIONSHIP_TYPE_NAME = 'Bundle to Bundle Component Relationship';
    private static final String INSTALLMENTS_GROUP_NAME_FALLBACK = 'Installments';
    private static final Integer INSTALLMENTS_GROUP_SEQUENCE_FALLBACK = 10;

    @InvocableMethod(label = 'Apply Approved POC To Future Payment Plan')
    public static void applyApprovedPOCToFuturePaymentPlan(List<Input> inputs){
        if(!inputs.isEmpty()){
            Set<Id> productCatalogIdSet = new Set<Id>();
            Map<Id, Id> pocToCatalogMap = new Map<Id, Id>();
            Map<Id, RES_Project_Completion_Report__c> pocRecordsMap = new Map<Id, RES_Project_Completion_Report__c>();
            for(Input inputObj : inputs){
                if(inputObj.pocRecord.RES_Project__c != null){
                    productCatalogIdSet.add(inputObj.pocRecord.RES_Project__c);
                    if(!pocToCatalogMap.containsKey(inputObj.pocRecord.Id)){
                        pocToCatalogMap.put(inputObj.pocRecord.Id, inputObj.pocRecord.RES_Project__c);
                    }
                    if(!pocRecordsMap.containsKey(inputObj.pocRecord.Id)){
                        pocRecordsMap.put(inputObj.pocRecord.Id, inputObj.pocRecord);
                    }
                }
            }

            if(!productCatalogIdSet.isEmpty()){
                List<Product2> productsLst = new RES_Product2DAOLayer().getProductsRelatedToCatalog(productCatalogIdSet, System.Label.RES_Product_Payment_Plan_RT);
                system.debug('productsLst ==> '+productsLst);
                if(!productsLst.isEmpty()){
                    cloneProducts(productsLst, pocToCatalogMap, pocRecordsMap);
                }
            }
        }
    }

    private static void cloneProducts(List<Product2> productsLst, Map<Id, Id> pocToCatalogMap, Map<Id, RES_Project_Completion_Report__c> pocRecordsMap){
        List<Product2> clonedProductsLst = new List<Product2>();
        /*
         * Every version clones from the ROOT (RES_Parent_Payment_Plan__c is always set to
         * productObj.Id below, i.e. the root plan, not the previous version) - versions fan out
         * flatly from the root rather than chaining v1 -> v2 -> v3. A Unit's PRC, however, always
         * points at whichever id was current, which could be the root (first approval) or any
         * prior version (later approvals) - so each clone's "superseded" set covers the root plus
         * every version that already exists for it, letting relinkUnitsToNewVersion find the Unit
         * regardless of which one it currently references.
         */
        List<Set<Id>> supersededIdsPerClone = new List<Set<Id>>();
        for(Product2 productObj : productsLst){
            Product2 clonedProduct = productObj.clone(false, true, false, false);
            clonedProduct.RES_Parent_Payment_Plan__c = productObj.Id;
            system.debug('productObj.ParentPaymentPlan__r ==> '+productObj.ParentPaymentPlan__r);
            Set<Id> supersededIds = new Set<Id>{ productObj.Id };
            if(productObj.ParentPaymentPlan__r != null && !productObj.ParentPaymentPlan__r.isEmpty()){
                clonedProduct.RES_Version__c = productObj.ParentPaymentPlan__r[0].RES_Version__c + 1;
                for(Product2 priorVersion : productObj.ParentPaymentPlan__r){
                    supersededIds.add(priorVersion.Id);
                }
            }
            else{
                clonedProduct.RES_Version__c = 1;
            }
            clonedProductsLst.add(clonedProduct);
            supersededIdsPerClone.add(supersededIds);
        }
        system.debug('clonedProductsLst ==> '+clonedProductsLst);
        if(!clonedProductsLst.isEmpty()){
            Database.SaveResult[] results = Database.insert(clonedProductsLst, false, AccessLevel.SYSTEM_MODE);
            for(Database.SaveResult result : results){
                if(!result.isSuccess()){
                    logFailure('Payment Plan (Product2) insert', null, result.getErrors());
                }
            }

            Map<Id, Set<Id>> parentToClonedProductsMap = new Map<Id, Set<Id>>();
            Map<Id, Id> oldIdToNewVersionMap = new Map<Id, Id>();
            for(Integer i = 0; i < clonedProductsLst.size(); i++){
                Product2 clonedProduct = clonedProductsLst[i];
                if(!parentToClonedProductsMap.containsKey(clonedProduct.RES_Parent_Payment_Plan__c)){
                    parentToClonedProductsMap.put(clonedProduct.RES_Parent_Payment_Plan__c, new Set<Id>{clonedProduct.Id});
                }
                else{
                    parentToClonedProductsMap.get(clonedProduct.RES_Parent_Payment_Plan__c).add(clonedProduct.Id);
                }
                for(Id supersededId : supersededIdsPerClone[i]){
                    oldIdToNewVersionMap.put(supersededId, clonedProduct.Id);
                }
            }

            if(parentToClonedProductsMap.size() > 0){
                cloneProductSellingModelOption(parentToClonedProductsMap);
                clonePriceBookEntries(parentToClonedProductsMap, true);
                clonePriceBookEntries(parentToClonedProductsMap, false);
                cloneInstallments(parentToClonedProductsMap, pocToCatalogMap, pocRecordsMap);
                relinkUnitsToNewVersion(oldIdToNewVersionMap);
            }
        }
    }

    private static void cloneProductSellingModelOption(Map<Id, Set<Id>> parentToClonedProductsMap){
        List<ProductSellingModelOption> parentSellingModelOptionsLst = new RES_ProductSellingModelOptionDAOLayer().getSellingModelOptionsByProductIds(parentToClonedProductsMap.keySet());
        if(!parentSellingModelOptionsLst.isEmpty()){
            List<ProductSellingModelOption> clonedSellingModelOptionsLst = new List<ProductSellingModelOption>();
            for(ProductSellingModelOption parentSellingOption : parentSellingModelOptionsLst) {
                if(parentToClonedProductsMap.get(parentSellingOption.Product2Id) != null){
                    for(Id clonedProductId : parentToClonedProductsMap.get(parentSellingOption.Product2Id)){
                        ProductSellingModelOption clonedSellingOption = parentSellingOption.clone(false, false, false, false);
                        clonedSellingOption.Product2Id = clonedProductId;
                        clonedSellingModelOptionsLst.add(clonedSellingOption);
                    }
                }
            }
            if(!clonedSellingModelOptionsLst.isEmpty()){
                Database.insert(clonedSellingModelOptionsLst, false, AccessLevel.SYSTEM_MODE);
            }
        }
    }

    private static void clonePriceBookEntries(Map<Id, Set<Id>> parentToClonedProductsMap, Boolean isStandard){
        List<PricebookEntry> parentPriceBookEntriesLst = new RES_PricebookEntryDAOLayer().getPricebookEntryRelatedToProducts(parentToClonedProductsMap.keySet(), isStandard);
        system.debug('parentPriceBookEntriesLst ==> '+parentPriceBookEntriesLst);
        if(!parentPriceBookEntriesLst.isEmpty()){
            List<PricebookEntry> clonedPriceBookEntriesLst = new List<PricebookEntry>();
            for(PricebookEntry parentPBE : parentPriceBookEntriesLst) {
                if(parentToClonedProductsMap.get(parentPBE.Product2Id) != null){
                    for(Id clonedProductId : parentToClonedProductsMap.get(parentPBE.Product2Id)){
                        PricebookEntry clonedPBE = parentPBE.clone(false, false, false, false);
                        clonedPBE.Product2Id = clonedProductId;
                        clonedPriceBookEntriesLst.add(clonedPBE);
                    }
                }
            }
            system.debug('clonedPriceBookEntriesLst ==> '+clonedPriceBookEntriesLst);
            if(!clonedPriceBookEntriesLst.isEmpty()){
                Database.SaveResult [] results = Database.insert(clonedPriceBookEntriesLst, false, AccessLevel.SYSTEM_MODE);
                for(Database.SaveResult result : results) {
                    if(!result.isSuccess()){
                        logFailure('PricebookEntry insert', null, result.getErrors());
                    }
                }
            }
        }
    }

    /**
     * Clones each root Payment Plan's Installments onto its new version, merging together
     * whichever leading installments' cumulative RES_POC_Percentage__c falls below the
     * approved POC% into a single installment, and carrying the rest over 1:1. Every cloned
     * installment is then linked to its new Payment Plan version via ProductRelatedComponent
     * (a fresh ProductComponentGroup mirroring the root's own), matching how installments are
     * wired on the very first version by RES_PaymentPlanConfiguratorService.
     */
    private static void cloneInstallments(Map<Id, Set<Id>> parentToClonedProductsMap, Map<Id, Id> pocToCatalogMap, Map<Id, RES_Project_Completion_Report__c> pocRecordsMap){
        List<ProductRelatedComponent> componentsLst = new RES_ProductRelatedComponentDAOLayer().getComponentsByParentProducts(parentToClonedProductsMap.keySet());
        if(componentsLst.isEmpty()){
            return;
        }

        Map<Id, Map<Id, List<ProductRelatedComponent>>> catalogToPlanComponentsMap = groupComponentsByCatalogAndPlan(componentsLst);

        Map<Id, List<InstallmentBuild>> installmentBuildsByRootPlan = new Map<Id, List<InstallmentBuild>>();
        List<Product2> clonedInstallments = new List<Product2>();

        for(Id pocId : pocToCatalogMap.keySet()){
            Decimal approvedPOC = pocRecordsMap.get(pocId).RES_POC__c;
            system.debug('approvedPOC ==> '+approvedPOC);
            Map<Id, List<ProductRelatedComponent>> planComponentsMap = catalogToPlanComponentsMap.get(pocToCatalogMap.get(pocId));
            if(planComponentsMap == null){
                continue;
            }
            for(Id rootPlanId : planComponentsMap.keySet()){
                List<InstallmentBuild> builds = buildInstallmentsForPlan(planComponentsMap.get(rootPlanId), approvedPOC, clonedInstallments);
                if(!builds.isEmpty()){
                    installmentBuildsByRootPlan.put(rootPlanId, builds);
                }
            }
        }

        if(clonedInstallments.isEmpty()){
            return;
        }
        Database.insert(clonedInstallments, false, AccessLevel.SYSTEM_MODE);

        linkInstallmentsToNewPlanVersions(parentToClonedProductsMap, installmentBuildsByRootPlan);
    }

    /**
     * Groups (root Payment Plan -> Installment) ProductRelatedComponent rows first by the
     * Payment Plan's catalog, then by the Payment Plan itself, so a bulk approval touching
     * several catalogs never mixes one catalog's installments into another's approved POC%.
     */
    private static Map<Id, Map<Id, List<ProductRelatedComponent>>> groupComponentsByCatalogAndPlan(List<ProductRelatedComponent> componentsLst){
        Map<Id, Map<Id, List<ProductRelatedComponent>>> catalogToPlanComponentsMap = new Map<Id, Map<Id, List<ProductRelatedComponent>>>();
        for(ProductRelatedComponent prc : componentsLst){
            Id catalogId = prc.ParentProduct.RES_Catalog__c;
            if(!catalogToPlanComponentsMap.containsKey(catalogId)){
                catalogToPlanComponentsMap.put(catalogId, new Map<Id, List<ProductRelatedComponent>>());
            }
            Map<Id, List<ProductRelatedComponent>> planComponentsMap = catalogToPlanComponentsMap.get(catalogId);
            if(!planComponentsMap.containsKey(prc.ParentProductId)){
                planComponentsMap.put(prc.ParentProductId, new List<ProductRelatedComponent>());
            }
            planComponentsMap.get(prc.ParentProductId).add(prc);
        }
        return catalogToPlanComponentsMap;
    }

    /**
     * Walks one Payment Plan's Installments in sequence order. RES_POC_Percentage__c on each
     * Installment is a cumulative completion MILESTONE (e.g. 20/40/70/100 - "due once we reach
     * this much overall completion"), not that installment's own incremental share - confirmed
     * against real org data. Any installment whose own milestone is already below the approved
     * POC% has effectively come due, so it's folded into a single merged installment (its
     * RES_Installment_Percentage__c becomes the sum of the merged group's shares - the amount now
     * due at once; its RES_POC_Percentage__c becomes the highest milestone among the merged group).
     * Every installment whose milestone the approved POC% hasn't reached yet is cloned 1:1, untouched.
     */
    private static List<InstallmentBuild> buildInstallmentsForPlan(List<ProductRelatedComponent> planComponents, Decimal approvedPOC, List<Product2> clonedInstallments){
        List<InstallmentBuild> builds = new List<InstallmentBuild>();
        Integer sequence = 0;
        InstallmentBuild mergedBuild;
        Decimal mergedInstallmentShareTotal = 0;

        for(ProductRelatedComponent prc : planComponents){
            Decimal installmentMilestone = prc.ChildProduct.RES_POC_Percentage__c;
            system.debug('installmentMilestone ==> '+installmentMilestone);
            if(installmentMilestone < approvedPOC){
                if(mergedBuild == null){
                    sequence++;
                    Product2 merged = cloneInstallmentProduct(prc.ChildProduct, sequence);
                    clonedInstallments.add(merged);
                    mergedBuild = new InstallmentBuild(merged, sequence, prc);
                    builds.add(mergedBuild);
                    mergedInstallmentShareTotal = 0;
                }
                mergedInstallmentShareTotal += prc.ChildProduct.RES_Installment_Percentage__c;
                mergedBuild.installment.RES_POC_Percentage__c = installmentMilestone;
                mergedBuild.installment.RES_Installment_Percentage__c = mergedInstallmentShareTotal;
                mergedBuild.percentage = mergedInstallmentShareTotal;
            }
            else{
                sequence++;
                Product2 installment = cloneInstallmentProduct(prc.ChildProduct, sequence);
                clonedInstallments.add(installment);
                builds.add(new InstallmentBuild(installment, sequence, prc));
            }
        }
        return builds;
    }

    private static Product2 cloneInstallmentProduct(Product2 childProduct, Integer sequence){
        return new Product2(
            Name = childProduct.Name,
            RecordTypeId = childProduct.RecordTypeId,
            RES_CIP_Type__c = childProduct.RES_CIP_Type__c,
            RES_Sequence__c = sequence,
            ProductCode = childProduct.ProductCode,
            RES_Instalment_DueDate__c = childProduct.RES_Instalment_DueDate__c,
            RES_Installment_Accumulative_Payments__c = childProduct.RES_Installment_Accumulative_Payments__c,
            RES_Installment_Construction_Progress__c = childProduct.RES_Installment_Construction_Progress__c,
            Description = childProduct.Description,
            IsActive = childProduct.IsActive,
            RES_Installment_Amount__c = childProduct.RES_Installment_Amount__c,
            CurrencyIsoCode = childProduct.CurrencyIsoCode,
            RES_POC_Percentage__c = childProduct.RES_POC_Percentage__c,
            RES_Installment_Percentage__c = childProduct.RES_Installment_Percentage__c
        );
    }

    /**
     * For each root Payment Plan that got new installments, creates a fresh Installments
     * ProductComponentGroup under the new Payment Plan version (mirroring the root's own
     * group Name/Sequence, sized to the new installment count) and the ProductRelatedComponent
     * rows linking the new version to each new installment - the piece the previous build left
     * out, without which a new version's installments are orphaned Product2 records with no
     * bundle structure. Also clones each new installment's ProductSellingModelOption and
     * PricebookEntry rows from its originating installment.
     */
    private static void linkInstallmentsToNewPlanVersions(Map<Id, Set<Id>> parentToClonedProductsMap, Map<Id, List<InstallmentBuild>> installmentBuildsByRootPlan){
        if(installmentBuildsByRootPlan.isEmpty()){
            return;
        }

        Map<Id, ProductComponentGroup> installmentGroupByRootPlan = mapGroupsByParent(
            new RES_ProductComponentGroupDAOLayer().getGroupsByParentProducts(installmentBuildsByRootPlan.keySet())
        );

        List<ProductComponentGroup> groupsToInsert = new List<ProductComponentGroup>();
        Map<Id, Id> newPlanIdByRootPlanId = new Map<Id, Id>();
        for(Id rootPlanId : installmentBuildsByRootPlan.keySet()){
            Set<Id> newPlanIds = parentToClonedProductsMap.get(rootPlanId);
            if(newPlanIds == null || newPlanIds.isEmpty()){
                continue;
            }
            Id newPlanId = new List<Id>(newPlanIds)[0];
            newPlanIdByRootPlanId.put(rootPlanId, newPlanId);

            Integer installmentCount = installmentBuildsByRootPlan.get(rootPlanId).size();
            ProductComponentGroup rootGroup = installmentGroupByRootPlan.get(rootPlanId);
            groupsToInsert.add(new ProductComponentGroup(
                ParentProductId = newPlanId,
                Name = rootGroup != null ? rootGroup.Name : INSTALLMENTS_GROUP_NAME_FALLBACK,
                Sequence = rootGroup != null ? rootGroup.Sequence : INSTALLMENTS_GROUP_SEQUENCE_FALLBACK,
                MinBundleComponents = installmentCount,
                MaxBundleComponents = installmentCount
            ));
        }
        if(groupsToInsert.isEmpty()){
            return;
        }

        Database.SaveResult[] groupResults = Database.insert(groupsToInsert, false, AccessLevel.SYSTEM_MODE);
        Map<Id, Id> groupIdByNewPlanId = new Map<Id, Id>();
        for(Integer i = 0; i < groupResults.size(); i++){
            if(groupResults[i].isSuccess()){
                groupIdByNewPlanId.put(groupsToInsert[i].ParentProductId, groupResults[i].getId());
            }
            else{
                logFailure('ProductComponentGroup insert', groupsToInsert[i].ParentProductId, groupResults[i].getErrors());
            }
        }

        Id relationshipTypeId = resolveBundleComponentRelationshipTypeId();
        if(relationshipTypeId == null){
            System.debug('RES_ApplyApprovedPOCToFuturePaymentPlan: ProductRelationshipType "' + BUNDLE_COMPONENT_RELATIONSHIP_TYPE_NAME + '" not found - cannot link installments to their new Payment Plan versions.');
            return;
        }

        List<ProductRelatedComponent> installmentComponentsToInsert = new List<ProductRelatedComponent>();
        Map<Id, Set<Id>> oldToNewInstallmentMap = new Map<Id, Set<Id>>();

        for(Id rootPlanId : installmentBuildsByRootPlan.keySet()){
            Id newPlanId = newPlanIdByRootPlanId.get(rootPlanId);
            Id groupId = newPlanId != null ? groupIdByNewPlanId.get(newPlanId) : null;
            if(newPlanId == null || groupId == null){
                continue;
            }
            for(InstallmentBuild build : installmentBuildsByRootPlan.get(rootPlanId)){
                installmentComponentsToInsert.add(new ProductRelatedComponent(
                    ParentProductId = newPlanId,
                    ChildProductId = build.installment.Id,
                    ProductComponentGroupId = groupId,
                    ProductRelationshipTypeId = relationshipTypeId,
                    Quantity = build.sourcePrc.Quantity,
                    IsComponentRequired = build.sourcePrc.IsComponentRequired,
                    IsDefaultComponent = build.sourcePrc.IsDefaultComponent,
                    IsQuantityEditable = build.sourcePrc.IsQuantityEditable,
                    DoesBundlePriceIncludeChild = build.sourcePrc.DoesBundlePriceIncludeChild,
                    QuoteVisibility = build.sourcePrc.QuoteVisibility,
                    Sequence = build.sequence * 10,
                    RES_Installment_Percentage__c = build.percentage
                ));

                if(!oldToNewInstallmentMap.containsKey(build.sourcePrc.ChildProductId)){
                    oldToNewInstallmentMap.put(build.sourcePrc.ChildProductId, new Set<Id>());
                }
                oldToNewInstallmentMap.get(build.sourcePrc.ChildProductId).add(build.installment.Id);
            }
        }

        if(!installmentComponentsToInsert.isEmpty()){
            Database.SaveResult[] prcResults = Database.insert(installmentComponentsToInsert, false, AccessLevel.SYSTEM_MODE);
            for(Integer i = 0; i < prcResults.size(); i++){
                if(!prcResults[i].isSuccess()){
                    logFailure('ProductRelatedComponent (installment link) insert', installmentComponentsToInsert[i].ParentProductId, prcResults[i].getErrors());
                }
            }
        }

        if(!oldToNewInstallmentMap.isEmpty()){
            cloneProductSellingModelOption(oldToNewInstallmentMap);
            clonePriceBookEntries(oldToNewInstallmentMap, true);
            clonePriceBookEntries(oldToNewInstallmentMap, false);
        }
    }

    /**
     * Repoints every existing Unit->Payment-Plan ProductRelatedComponent (created originally by
     * RES_PaymentPlanBundleProvisioner) from the previous Payment Plan version to the new one.
     * ChildProductId cannot be changed by updating the existing row in place - confirmed against
     * the real org, Database.update reports success but silently leaves ChildProductId
     * unchanged - so each Unit's component is replaced: a new row is inserted first (carrying
     * over the old row's configuration, including RES_Price_Option__c, the field
     * RES_ResidentialBundlePricingHook depends on to price the Unit), and only once that insert
     * succeeds is the old row deleted. Insert-before-delete means a failure never leaves the Unit
     * with zero Payment Plan components; the Unit's "Payment Plan" group enforces exactly one
     * (Min=Max=1) but that is only validated at quote-configuration time, not on this catalog-level
     * metadata DML, so the brief moment with two rows is safe. This only affects future
     * configuration/quoting for the Unit, not any already transacted quote or order.
     */
    private static void relinkUnitsToNewVersion(Map<Id, Id> oldIdToNewVersionMap){
        if(oldIdToNewVersionMap.isEmpty()){
            return;
        }
        List<ProductRelatedComponent> unitComponents = new RES_ProductRelatedComponentDAOLayer().getComponentsByChildProducts(oldIdToNewVersionMap.keySet());
        if(unitComponents.isEmpty()){
            return;
        }

        List<ProductRelatedComponent> oldComponentsToReplace = new List<ProductRelatedComponent>();
        List<ProductRelatedComponent> newUnitComponents = new List<ProductRelatedComponent>();
        for(ProductRelatedComponent unitComponent : unitComponents){
            Id newPlanId = oldIdToNewVersionMap.get(unitComponent.ChildProductId);
            if(newPlanId == null){
                continue;
            }
            oldComponentsToReplace.add(unitComponent);
            newUnitComponents.add(new ProductRelatedComponent(
                ParentProductId = unitComponent.ParentProductId,
                ChildProductId = newPlanId,
                ProductComponentGroupId = unitComponent.ProductComponentGroupId,
                ProductRelationshipTypeId = unitComponent.ProductRelationshipTypeId,
                Quantity = unitComponent.Quantity,
                IsComponentRequired = unitComponent.IsComponentRequired,
                IsDefaultComponent = unitComponent.IsDefaultComponent,
                IsQuantityEditable = unitComponent.IsQuantityEditable,
                DoesBundlePriceIncludeChild = unitComponent.DoesBundlePriceIncludeChild,
                QuoteVisibility = unitComponent.QuoteVisibility,
                RES_Price_Option__c = unitComponent.RES_Price_Option__c
            ));
        }

        if(newUnitComponents.isEmpty()){
            return;
        }

        Database.SaveResult[] insertResults = Database.insert(newUnitComponents, false, AccessLevel.SYSTEM_MODE);
        List<ProductRelatedComponent> oldComponentsToDelete = new List<ProductRelatedComponent>();
        for(Integer i = 0; i < insertResults.size(); i++){
            if(insertResults[i].isSuccess()){
                oldComponentsToDelete.add(oldComponentsToReplace[i]);
            }
            else{
                logFailure('ProductRelatedComponent (Unit relink) insert', newUnitComponents[i].ParentProductId, insertResults[i].getErrors());
            }
        }

        if(!oldComponentsToDelete.isEmpty()){
            Database.DeleteResult[] deleteResults = Database.delete(oldComponentsToDelete, false);
            for(Integer i = 0; i < deleteResults.size(); i++){
                if(!deleteResults[i].isSuccess()){
                    logFailure('ProductRelatedComponent (superseded Unit link) delete', oldComponentsToDelete[i].Id, deleteResults[i].getErrors());
                }
            }
        }
    }

    private static Id resolveBundleComponentRelationshipTypeId(){
        ProductRelationshipType relationshipType = new RES_ProductRelationshipTypeDAOLayer().getByName(BUNDLE_COMPONENT_RELATIONSHIP_TYPE_NAME);
        return relationshipType == null ? null : relationshipType.Id;
    }

    private static Map<Id, ProductComponentGroup> mapGroupsByParent(List<ProductComponentGroup> groups){
        Map<Id, ProductComponentGroup> result = new Map<Id, ProductComponentGroup>();
        for(ProductComponentGroup componentGroup : groups){
            result.put(componentGroup.ParentProductId, componentGroup);
        }
        return result;
    }

    private static void logFailure(String operation, Id recordId, List<Database.Error> errors){
        List<String> messages = new List<String>();
        for(Database.Error err : errors){
            messages.add(err.getStatusCode() + ': ' + err.getMessage());
        }
        System.debug('RES_ApplyApprovedPOCToFuturePaymentPlan: ' + operation + ' failed' + (recordId != null ? ' for ' + recordId : '') + ' - ' + String.join(messages, '; '));
    }

    /** Tracks one new installment being built: its clone, its position, its (possibly merged) percentage, and the original ProductRelatedComponent it was cloned from. */
    private class InstallmentBuild {
        private Product2 installment;
        private Integer sequence;
        private Decimal percentage;
        private ProductRelatedComponent sourcePrc;

        private InstallmentBuild(Product2 installment, Integer sequence, ProductRelatedComponent sourcePrc){
            this.installment = installment;
            this.sequence = sequence;
            this.percentage = sourcePrc.ChildProduct.RES_Installment_Percentage__c;
            this.sourcePrc = sourcePrc;
        }
    }

    public class Input {
        @InvocableVariable public RES_Project_Completion_Report__c pocRecord;
    }
}