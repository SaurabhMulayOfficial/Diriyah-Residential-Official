// Sequential delete of Product2 inventory records (and everything the Product Inventory
// Upload Framework creates under them). Based on Yogesh's script; adds the Service Charge
// bundle (ProductRelatedComponent / ProductComponentGroup) and the staging rows.
//
// Run in Anonymous Apex. Re-run until "Products found: 0" - each run is capped so the
// delete itself stays under the 10,000 DML row limit.
//
//   deleteAll = true  -> every Product2 that has an external ID or product code (DESTRUCTIVE, never in UAT/Prod)
//   deleteAll = false -> only extIds and/or codePrefix below (matched on ProductCode or external ID)

Boolean deleteAll = false;
Integer maxProducts = 25;
String codePrefix = 'WS-FN-BULK-';
// Exact product codes to delete. Keep this EMPTY unless you mean it: every listed code is wiped.
List<String> extIds = new List<String>();

String prefixLike = String.isBlank(codePrefix) ? null : codePrefix + '%';

List<Product2> products = deleteAll
  ? [SELECT Id, Name, ProductCode, RES_Product_External_ID__c FROM Product2
    WHERE RES_Product_External_ID__c != NULL OR ProductCode != NULL LIMIT :maxProducts]
  : [SELECT Id, Name, ProductCode, RES_Product_External_ID__c FROM Product2
    WHERE RES_Product_External_ID__c IN :extIds
    OR ProductCode IN :extIds
    OR (ProductCode LIKE :prefixLike AND ProductCode != NULL)
    LIMIT :maxProducts];

Set<Id> pids = new Map<Id, Product2>(products).keySet();
Set<String> codes = new Set<String>();
// The unit code is in ProductCode; RES_Product_External_ID__c can be blank until the SAP sync fills it.
for (Product2 p : products) {
  if (p.ProductCode != null) codes.add(p.ProductCode);
  if (p.RES_Product_External_ID__c != null) codes.add(p.RES_Product_External_ID__c);
}

System.debug('Products found: ' + products.size());

if (!pids.isEmpty()) {

  // Attribute Adjustment Rules
  Set<Id> ruleIds = new Set<Id>();
  for (AttributeAdjustmentCondition c : [
    SELECT AttributeBasedAdjRuleId
    FROM AttributeAdjustmentCondition
    WHERE ProductId IN :pids
    AND AttributeBasedAdjRuleId != NULL
  ]) {
    ruleIds.add(c.AttributeBasedAdjRuleId);
  }

  if (!ruleIds.isEmpty())
    Database.delete([
      SELECT Id FROM AttributeBasedAdjRule
      WHERE Id IN :ruleIds
    ], false);

  // Service Charge bundle: components first, then their groups
  Database.delete([
    SELECT Id FROM ProductRelatedComponent
    WHERE ParentProductId IN :pids
  ], false);

  Database.delete([
    SELECT Id FROM ProductComponentGroup
    WHERE ParentProductId IN :pids
  ], false);

  // Product dependencies
  Database.delete([
    SELECT Id FROM RES_Measurement__c
    WHERE RES_Product__c IN :pids
  ], false);

  Database.delete([
    SELECT Id FROM AttributeBasedAdjustment
    WHERE ProductId IN :pids
  ], false);

  Database.delete([
    SELECT Id FROM ProductAttributeDefinition
    WHERE Product2Id IN :pids
  ], false);

  Database.delete([
    SELECT Id FROM ProductCategoryProduct
    WHERE ProductId IN :pids
  ], false);

  Database.delete([
    SELECT Id FROM ProductDisqualification
    WHERE ProductId IN :pids
  ], false);

  Database.delete([
    SELECT Id FROM ProductSellingModelOption
    WHERE Product2Id IN :pids
  ], false);

  // Custom Pricebook Entries FIRST
  Database.delete([
    SELECT Id FROM PricebookEntry
    WHERE Product2Id IN :pids
    AND Pricebook2.IsStandard = false
  ], false);

  // Standard Pricebook Entries SECOND
  Database.delete([
    SELECT Id FROM PricebookEntry
    WHERE Product2Id IN :pids
    AND Pricebook2.IsStandard = true
  ], false);

  // Final dependency check
  Integer remaining = [SELECT COUNT() FROM PricebookEntry WHERE Product2Id IN :pids];
  remaining += [SELECT COUNT() FROM RES_Measurement__c WHERE RES_Product__c IN :pids];
  remaining += [SELECT COUNT() FROM ProductAttributeDefinition WHERE Product2Id IN :pids];
  remaining += [SELECT COUNT() FROM ProductCategoryProduct WHERE ProductId IN :pids];
  remaining += [SELECT COUNT() FROM ProductDisqualification WHERE ProductId IN :pids];
  remaining += [SELECT COUNT() FROM ProductSellingModelOption WHERE Product2Id IN :pids];
  remaining += [SELECT COUNT() FROM AttributeAdjustmentCondition WHERE ProductId IN :pids];
  remaining += [SELECT COUNT() FROM ProductRelatedComponent WHERE ParentProductId IN :pids];
  remaining += [SELECT COUNT() FROM ProductComponentGroup WHERE ParentProductId IN :pids];

  if (remaining == 0) {
    Database.DeleteResult[] r = Database.delete(products, false);

    for (Integer i = 0; i < r.size(); i++)
      System.debug(
        'Product ' + products[i].Name +
        ' deleted = ' + r[i].isSuccess()
      );

    // Staging rows for the deleted units (re-uploading the same codes starts clean)
    Database.delete([
      SELECT Id FROM RES_Product_Staging__c
      WHERE RES_Product_Code__c IN :codes
    ], false);
  } else {
    System.debug(
      'Product2 NOT deleted. Remaining dependencies = ' +
      remaining
    );
  }
}
