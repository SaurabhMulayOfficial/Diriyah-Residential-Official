/** Tests for RES_ProductSCRateValidation (SeeAllData=true, so no @testSetup - reuses the org's real 'Service_Charge_Rate'-named AttributeDefinition, whose DeveloperName is unique org-wide). */
@isTest(SeeAllData=true)
private class RES_ProductSCRateValidationTest {

    private static final String PRODUCT_NAME = 'RES Test SC Rate Validation Product';

    /** Grants the shared permission set (needed for ProductAttributeDefinition DML) and creates the test product on the given record type (or the default record type if null), both in this method's own transaction. */
    private static Product2 setupProductWithPermission(Id recordTypeId) {
        List<PermissionSetAssignment> existingAssignments = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
                AND PermissionSet.Name = 'RES_Revenue_Cloud_Objects'
        ];
        if (existingAssignments.isEmpty()) {
            List<PermissionSet> permSets = [
                SELECT Id FROM PermissionSet WHERE Name = 'RES_Revenue_Cloud_Objects' LIMIT 1
            ];
            if (!permSets.isEmpty()) {
                insert new PermissionSetAssignment(
                    AssigneeId = UserInfo.getUserId(),
                    PermissionSetId = permSets[0].Id
                );
            }
        }

        Product2 product = new Product2(
            Name = PRODUCT_NAME,
            ProductCode = 'RES-TEST-SCRATE-VALIDATION-001',
            IsActive = false,
            RES_Unit_Status__c = 'Draft',
            RecordTypeId = recordTypeId
        );
        insert product;
        return product;
    }

    private static Product2 setupProductWithPermission() {
        return setupProductWithPermission(residentialSalesRecordTypeId());
    }

    private static Id residentialSalesRecordTypeId() {
        return Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName().get('RES_Residential_Sales').getRecordTypeId();
    }

    /** Creates the Service Charge Rate ProductAttributeDefinition override on the given product, reusing the org's real AttributeDefinition (DeveloperName is unique org-wide). */
    private static void insertServiceChargeRateOverride(Id productId) {
        String scRateDeveloperName = Label.RES_Service_Charge_Rate_Attribute;

        List<AttributeDefinition> existingScRateAttrs = [
            SELECT Id FROM AttributeDefinition WHERE DeveloperName = :scRateDeveloperName LIMIT 1
        ];
        AttributeDefinition scRateAttr;
        if (!existingScRateAttrs.isEmpty()) {
            scRateAttr = existingScRateAttrs[0];
        } else {
            scRateAttr = new AttributeDefinition(
                Name = 'RES Test SC Rate Validation Attribute', Label = 'RES Test SC Rate Validation Attribute',
                DeveloperName = scRateDeveloperName, DataType = 'Number', IsActive = true
            );
            insert scRateAttr;
        }

        // ProductAttributeDefinition.ProductClassificationAttributeId is required in this org -
        // reuse the org's real ProductClassificationAttr for this AttributeDefinition, since
        // creating a fresh classification chain isn't necessary just to satisfy this field
        List<ProductClassificationAttr> existingClassificationAttrs = [
            SELECT Id, ProductClassificationId FROM ProductClassificationAttr WHERE AttributeDefinitionId = :scRateAttr.Id LIMIT 1
        ];
        ProductClassificationAttr classificationAttr;
        if (!existingClassificationAttrs.isEmpty()) {
            classificationAttr = existingClassificationAttrs[0];
        } else {
            ProductClassification classification = new ProductClassification(
                Code = 'RES_TEST_SCRATE_VALIDATION_' + String.valueOf(Crypto.getRandomInteger()).right(8),
                Name = 'RES Test SC Rate Validation Classification',
                Status = 'Active'
            );
            insert classification;
            classificationAttr = new ProductClassificationAttr(
                Name = 'RES Test SC Rate Validation Classification Attr',
                ProductClassificationId = classification.Id,
                AttributeDefinitionId = scRateAttr.Id
            );
            insert classificationAttr;
        }

        // Product2.BasedOnId must match the ProductClassificationAttr's own classification
        update new Product2(Id = productId, BasedOnId = classificationAttr.ProductClassificationId);

        insert new ProductAttributeDefinition(
            Name = 'RES Test SC Rate Validation Override',
            ProductClassificationAttributeId = classificationAttr.Id,
            Product2Id = productId,
            AttributeDefinitionId = scRateAttr.Id,
            DefaultValue = '120'
        );
    }

    /** Test: Setting IsActive = true without the Service Charge Rate override configured is blocked. */
    @isTest
    static void testValidate_BlocksActiveWithoutServiceChargeRate() {
        Product2 product = setupProductWithPermission();

        Test.startTest();
        product.IsActive = true;
        Database.SaveResult result = Database.update(product, false);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Setting Active without the Service Charge Rate override should be blocked');
        System.assert(
            result.getErrors()[0].getMessage().contains('Service Charge Rate attribute override is not configured'),
            'Error message should explain the missing Service Charge Rate override'
        );
    }

    /** Test: Setting IsActive = true with the Service Charge Rate override configured succeeds. */
    @isTest
    static void testValidate_AllowsActiveWithServiceChargeRate() {
        Product2 product = setupProductWithPermission();
        insertServiceChargeRateOverride(product.Id);

        Test.startTest();
        product.IsActive = true;
        Database.SaveResult result = Database.update(product, false);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Setting Active with the Service Charge Rate override present should succeed');
    }

    /** Test: Setting RES_Unit_Status__c = 'Available' without the Service Charge Rate override configured is blocked. */
    @isTest
    static void testValidate_BlocksAvailableWithoutServiceChargeRate() {
        Product2 product = setupProductWithPermission();

        Test.startTest();
        product.RES_Unit_Status__c = 'Available';
        Database.SaveResult result = Database.update(product, false);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Setting Unit Status to Available without the Service Charge Rate override should be blocked');
        System.assert(
            result.getErrors()[0].getMessage().contains('Service Charge Rate attribute override is not configured'),
            'Error message should explain the missing Service Charge Rate override'
        );
    }

    /** Test: Setting RES_Unit_Status__c = 'Available' with the Service Charge Rate override configured succeeds. */
    @isTest
    static void testValidate_AllowsAvailableWithServiceChargeRate() {
        Product2 product = setupProductWithPermission();
        insertServiceChargeRateOverride(product.Id);

        Test.startTest();
        product.RES_Unit_Status__c = 'Available';
        Database.SaveResult result = Database.update(product, false);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Setting Unit Status to Available with the Service Charge Rate override present should succeed');
    }

    /** Test: Updating an unrelated field neither turns the product Active nor its Unit Status Available, so no validation is triggered. */
    @isTest
    static void testValidate_UnrelatedFieldChangeSkipsValidation() {
        Product2 product = setupProductWithPermission();

        Test.startTest();
        product.Description = 'Unrelated update';
        Database.SaveResult result = Database.update(product, false);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'A field change unrelated to Active/Available should never be blocked');
    }

    /** Test: a non-Residential Sales record type (e.g. Residential Installment) is exempt - it can be set Active without the Service Charge Rate override, since this validation only applies to units. */
    @isTest
    static void testValidate_NonResidentialSalesRecordTypeIsExempt() {
        Id installmentRecordTypeId = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName().get('RES_Residential_Installment').getRecordTypeId();
        Product2 product = setupProductWithPermission(installmentRecordTypeId);

        Test.startTest();
        product.IsActive = true;
        Database.SaveResult result = Database.update(product, false);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'A non-Residential Sales record type should be exempt from this validation entirely');
    }

    /** Test: turningActive/turningAvailable helper semantics - true only on a genuine transition into that state. */
    @isTest
    static void testTurningActiveAndTurningAvailable_HelperSemantics() {
        Product2 wasInactive = new Product2(IsActive = false, RES_Unit_Status__c = 'Draft');
        Product2 nowActive = new Product2(IsActive = true, RES_Unit_Status__c = 'Draft');
        Product2 stillActive = new Product2(IsActive = true, RES_Unit_Status__c = 'Draft');
        Product2 nowAvailable = new Product2(IsActive = false, RES_Unit_Status__c = 'Available');
        Product2 stillAvailable = new Product2(IsActive = false, RES_Unit_Status__c = 'Available');

        Test.startTest();
        Boolean turningActiveTrue = RES_ProductSCRateValidation.turningActive(nowActive, wasInactive);
        Boolean turningActiveFalse = RES_ProductSCRateValidation.turningActive(stillActive, nowActive);
        Boolean turningAvailableTrue = RES_ProductSCRateValidation.turningAvailable(nowAvailable, wasInactive);
        Boolean turningAvailableFalse = RES_ProductSCRateValidation.turningAvailable(stillAvailable, nowAvailable);
        Test.stopTest();

        System.assertEquals(true, turningActiveTrue, 'Should detect a transition from inactive to active');
        System.assertEquals(false, turningActiveFalse, 'Should not flag a product that was already active');
        System.assertEquals(true, turningAvailableTrue, 'Should detect a transition into Available status');
        System.assertEquals(false, turningAvailableFalse, 'Should not flag a product that was already Available');
    }

    /** Test: validate() is a no-op when oldMap is null (e.g. called outside a genuine update context). */
    @isTest
    static void testValidate_NullOldMapIsNoOp() {
        Product2 product = new Product2(Name = 'RES Test Null OldMap', IsActive = true);

        Test.startTest();
        RES_ProductSCRateValidation.validate(new List<Product2>{product}, null);
        Test.stopTest();

        System.assertEquals(null, product.Id, 'No DML/addError should occur - this is purely confirming no exception is thrown');
    }
}
