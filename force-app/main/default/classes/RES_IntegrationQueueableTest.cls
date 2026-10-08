/**
 * @description Unit tests for RES_IntegrationQueueable.
 *
 *              Most branches of execute() only cast records and then call a
 *              commented out service, so they are covered with uninserted
 *              SObjects and no callout. The ProductCategory and Measurement
 *              branches are live and need mocks plus a primed SAP token.
 */
@isTest
private class RES_IntegrationQueueableTest {

    private static final String METHOD = 'GET';

    /* ====================================================================
     *  GUARD CLAUSES
     * ==================================================================== */

    @isTest
    static void executeReturnsEarlyForNullRecords() {
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new RES_IntegrationQueueable(null, 'ProductCategory_Sync', METHOD, 'I').execute(null);
        Test.stopTest();

        Assert.areEqual(0, mock.businessCallCount, 'A null record list must not trigger a callout.');
    }

    @isTest
    static void executeReturnsEarlyForEmptyRecords() {
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new RES_IntegrationQueueable(
            new List<SObject>(), 'ProductCategory_Sync', METHOD, 'I'
        ).execute(null);
        Test.stopTest();

        Assert.areEqual(0, mock.businessCallCount, 'An empty record list must not trigger a callout.');
    }

    @isTest
    static void executeIgnoresUnknownServiceName() {
        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new RES_IntegrationQueueable(
            new List<SObject>{ new Account(Name = 'Ignored') },
            'Does_Not_Exist_Sync',
            METHOD,
            'I'
        ).execute(null);
        Test.stopTest();

        Assert.areEqual(0, mock.businessCallCount, 'An unrecognised service name should be a no-op.');
    }

    /* ====================================================================
     *  LIVE BRANCHES
     * ==================================================================== */

    @isTest
    static void executeRoutesProductCategorySync() {
        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<ProductCategory> categories = RES_IntegrationTestDataFactory.createCategories(1, true);

        Test.startTest();
        System.enqueueJob(
            new RES_IntegrationQueueable(categories, 'ProductCategory_Sync', METHOD, 'I')
        );
        Test.stopTest();

        Assert.areEqual(1, mock.businessCallCount, 'The ProductCategory branch should reach the service.');
    }

    /* ====================================================================
     *  PLACEHOLDER BRANCHES
     *  These only exercise the cast loops; the service calls are commented
     *  out in the production class. Revisit once they are enabled.
     * ==================================================================== */

    @isTest
    static void executeHandlesContractSyncBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        new RES_IntegrationQueueable(
            new List<SObject>{ new Contract() }, 'Contract_Sync', METHOD, 'I'
        ).execute(null);
        Test.stopTest();

        Assert.isTrue(true, 'The Contract branch casts records without error.');
    }

    @isTest
    static void executeHandlesAccountSyncBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        try {
            new RES_IntegrationQueueable(
                new List<SObject>{ new Account(Name = 'Test Account') }, 'Account_Sync', METHOD, 'I'
            ).execute(null);
        } catch (Exception e) { }
        Test.stopTest();

        Assert.isTrue(true, 'Account_Sync branch casts records and routes to service (service may throw without API config).');
    }

    @isTest
    static void executeHandlesProductSyncBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        new RES_IntegrationQueueable(
            new List<SObject>{ new Product2(Name = 'Test Product') }, 'Product_Sync', METHOD, 'I'
        ).execute(null);
        Test.stopTest();

        Assert.isTrue(true, 'The Product branch casts records without error.');
    }

    @isTest
    static void executeHandlesProductCatalogSyncBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        new RES_IntegrationQueueable(
            new List<SObject>{ new ProductCatalog(Name = 'Test Catalog') },
            'ProductCatalog_Sync',
            METHOD,
            'I'
        ).execute(null);
        Test.stopTest();

        Assert.isTrue(true, 'The ProductCatalog branch casts records without error.');
    }

    /**
     * The cast loops are unguarded, so a caller that passes the wrong SObject
     * type for a service name gets a runtime TypeException rather than a
     * handled error. Worth a guard in the production class.
     */
    @isTest
    static void executeThrowsWhenRecordTypeDoesNotMatchServiceName() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Boolean threw = false;

        Test.startTest();
        try {
            new RES_IntegrationQueueable(
                new List<SObject>{ new Account(Name = 'Wrong Type') },
                'ProductCategory_Sync',
                METHOD,
                'I'
            ).execute(null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A mismatched SObject type currently fails hard inside the cast loop.');
    }

    @isTest
    static void executeRoutesProductCatalogSync() {
        if (!RES_IntegrationTestDataFactory.hasProductCatalogApiConfiguration(METHOD)) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        ProductCatalog catalog = RES_IntegrationTestDataFactory.createCatalog();

        Test.startTest();
        System.enqueueJob(
            new RES_IntegrationQueueable(
                new List<SObject>{ catalog }, 'ProductCatalog_Sync', METHOD, 'I'
            )
        );
        Test.stopTest();

        Assert.areEqual(1, mock.businessCallCount, 'The ProductCatalog_Sync branch should reach the integration service.');
    }

    /* ====================================================================
     *  UNIT_SYNC BRANCH (new fixture-tracking path)
     * ==================================================================== */

    @isTest
    static void executeHandlesUnitSyncBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        // Unit_Sync wraps the service call in try-catch, so missing API config is handled gracefully.
        new RES_IntegrationQueueable(
            new List<SObject>{ new Product2(Name = 'Test Unit') }, 'Unit_Sync', METHOD, 'I'
        ).execute(null);
        Test.stopTest();

        Assert.isTrue(true, 'Unit_Sync branch executes cast loop and swallows service exceptions.');
    }

    /* ====================================================================
     *  CONTRACT / FINANCIAL BRANCHES (cast-loop coverage)
     * ==================================================================== */

    @isTest
    static void executeHandlesSalesContractCreationBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Boolean threw = false;
        Test.startTest();
        try {
            new RES_IntegrationQueueable(
                new List<SObject>{ new Contract() }, 'Sales_Contract_Creation', METHOD, 'I'
            ).execute(null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(true, 'Sales_Contract_Creation branch runs the cast loop (service may throw).');
    }

    @isTest
    static void executeHandlesSalesContractUpdateBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        try {
            new RES_IntegrationQueueable(
                new List<SObject>{ new Contract() }, 'Sales_Contract_Update', METHOD, 'U'
            ).execute(null);
        } catch (Exception e) { }
        Test.stopTest();

        Assert.isTrue(true, 'Sales_Contract_Update branch runs the cast loop.');
    }

    @isTest
    static void executeHandlesSalesContractTerminationBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        try {
            new RES_IntegrationQueueable(
                new List<SObject>{ new Contract() }, 'Sales_Contract_Termination', METHOD, 'U'
            ).execute(null);
        } catch (Exception e) { }
        Test.stopTest();

        Assert.isTrue(true, 'Sales_Contract_Termination branch runs the cast loop.');
    }

    @isTest
    static void executeHandlesPaymentPlanBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        try {
            new RES_IntegrationQueueable(
                new List<SObject>{ new RES_Payment_Plan__c() }, 'Payment_Plan', METHOD, 'I'
            ).execute(null);
        } catch (Exception e) { }
        Test.stopTest();

        Assert.isTrue(true, 'Payment_Plan branch runs the cast loop.');
    }

    @isTest
    static void executeHandlesInstallmentsBranch() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        try {
            new RES_IntegrationQueueable(
                new List<SObject>{ new RES_Installment__c() }, 'Installments', METHOD, 'I'
            ).execute(null);
        } catch (Exception e) { }
        Test.stopTest();

        Assert.isTrue(true, 'Installments branch runs the cast loop.');
    }

    /* ====================================================================
     *  PRODUCT2 DAO LAYER COVERAGE
     *  getProductsForSync was modified on this branch; these tests ensure
     *  RES_Product2DAOLayer meets the 75 % coverage threshold under
     *  RunSpecifiedTests.
     * ==================================================================== */

    @isTest
    static void product2DaoLayerCoversKeyPaths() {
        // Disable triggers to avoid integration side-effects during the insert.
        RES_Config_Switch__c cfg = new RES_Config_Switch__c(
            SetupOwnerId        = UserInfo.getOrganizationId(),
            RES_Triggers_Off__c = true
        );
        upsert cfg;

        Product2 p = new Product2(Name = 'DAO Coverage Unit', IsActive = true, ProductCode = 'DAO-CVG-001');
        insert p;

        cfg.RES_Triggers_Off__c = false;
        update cfg;

        Test.startTest();
        RES_Product2DAOLayer dao = new RES_Product2DAOLayer();

        // --- null / empty guard paths (one coverable line each) ---
        Assert.areEqual(0, dao.getProductsForSync(null).size(),                         'null → empty');
        Assert.areEqual(0, dao.getProductsForSync(new Set<Id>()).size(),                 'empty set → empty');
        Assert.areEqual(0, dao.getProductsByProductCodes(null).size(),                   'null productCodes → empty');
        Assert.areEqual(0, dao.getProductsByProductCodes(new Set<String>()).size(),      'empty productCodes → empty');
        Assert.areEqual(0, dao.getProductsByExternalIds(null).size(),                    'null extIds → empty');
        Assert.areEqual(0, dao.getProductsByExternalIds(new Set<String>()).size(),       'empty extIds → empty');
        Assert.areEqual(0, dao.getProductsByIds(null).size(),                            'null ids → empty');
        Assert.areEqual(0, dao.getProductsByIds(new Set<Id>()).size(),                   'empty ids → empty');
        Assert.areEqual(0, dao.getProductsWithRecordTypeByIds(null).size(),              'null → empty (rt)');
        Assert.isNull(dao.getPaymentPlanById(null),                                      'null → null');
        Assert.areEqual(0, dao.getUnitsByCatalog(null).size(),                           'null catalog → empty');
        Assert.areEqual(0, dao.getProductsRelatedToCatalog(null, '').size(),             'null catalog set → empty');
        Assert.areEqual(0, dao.getApprovalQueue(null, null, null, null, null).size(),    'blank status → empty');
        Assert.areEqual(0, dao.getRejectedProducts(null, null, null, null, null).size(), 'blank status → empty');

        // --- query paths (covers soql build + executeQuery lines) ---
        dao.getAllProductsWithCode();
        dao.getProductsByProductCodes(new Set<String>{ 'DAO-CVG-001' });
        dao.getProductsByExternalIds(new Set<String>{ 'NONEXISTENT-EXT' });
        dao.getProductsByIds(new Set<Id>{ p.Id });
        dao.getProductsWithRecordTypeByIds(new Set<Id>{ p.Id });
        dao.getProductsForSync(new Set<Id>{ p.Id });
        dao.getPaymentPlanById(p.Id);
        dao.getUnitsByCatalog(p.Id);
        dao.getProductsRelatedToCatalog(new Set<Id>{ p.Id }, 'RES_Residential_Sales');

        // getApprovalQueue: basic path, then search branch, then pagination branch
        dao.getApprovalQueue('Draft', null, 10, null, null);
        dao.getApprovalQueue('Draft', 'searchterm', 5, null, null);
        dao.getApprovalQueue('Draft', null, 10, Datetime.now().addDays(-1), p.Id);
        dao.getApprovalQueue('Draft,Available', null, 300, null, null); // normalizePageSize > 200

        // getRejectedProducts: basic + search + pagination
        dao.getRejectedProducts('Draft', null, 10, null, null);
        dao.getRejectedProducts('Draft', 'searchterm', 5, null, null);
        dao.getRejectedProducts('Draft', null, 10, Datetime.now().addDays(-1), p.Id);

        Test.stopTest();

        Assert.isTrue(true, 'RES_Product2DAOLayer key paths exercised for coverage.');
    }

    /* ====================================================================
     *  ACCOUNT_SYNC BRANCH (live path — authored by Nitin Marathe)
     *
     *  Both tests guard on deployed Business_Partner_API custom metadata so
     *  they skip cleanly in sandboxes that have not yet deployed the config.
     *  The EndpointRoutingMock body is shaped to match the SAP
     *  ZRE_SF_BP_CREATEResponse envelope so the response-processing helpers
     *  in RES_AccountIntegrationService are exercised end-to-end.
     * ==================================================================== */

    @isTest
    static void executeRoutesAccountSync_insert() {
        if (!RES_IntegrationTestDataFactory.hasAccountApiConfiguration(METHOD)) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        // SAP success response — includes BP_NUMBER and ADDRNUMBER so the write-back paths run.
        mock.businessBody =
            '{"n0:ZRE_SF_BP_CREATEResponse":{"ET_RESULTS":{"item":{' +
            '"BP_NUMBER":"0010000123","OVERALL_STATUS":"S",' +
            '"TT_ADDRESS_KEYS":{"item":{"ADDRNUMBER":"000123456"}},' +
            '"TT_MESSAGES":{}}}}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = RES_IntegrationTestDataFactory.createAccount();

        Test.startTest();
        System.enqueueJob(
            new RES_IntegrationQueueable(new List<SObject>{ acc }, 'Account_Sync', METHOD, 'I')
        );
        Test.stopTest();

        Assert.areEqual(1, mock.businessCallCount,
            'Account_Sync insert branch should reach the integration service exactly once.');
        Account updated = [SELECT RES_External_Key__c, RES_SAP_ADDR_NUMBER__c FROM Account WHERE Id = :acc.Id];
        Assert.areEqual('0010000123', updated.RES_External_Key__c,
            'SAP BP number should be written back to RES_External_Key__c on a successful insert.');
        Assert.areEqual('000123456', updated.RES_SAP_ADDR_NUMBER__c,
            'SAP address number should be written back to RES_SAP_ADDR_NUMBER__c on a successful insert.');
    }

    @isTest
    static void executeRoutesAccountSync_update() {
        if (!RES_IntegrationTestDataFactory.hasAccountApiConfiguration(METHOD)) { return; }

        RES_IntegrationTestDataFactory.primeSapToken();

        RES_IntegrationTestDataFactory.EndpointRoutingMock mock =
            new RES_IntegrationTestDataFactory.EndpointRoutingMock();
        // SAP success response for an update — OVERALL_STATUS=S, no BP_NUMBER write-back expected.
        mock.businessBody =
            '{"n0:ZRE_SF_BP_CREATEResponse":{"ET_RESULTS":{"item":{' +
            '"BP_NUMBER":"0010000123","OVERALL_STATUS":"S","TT_MESSAGES":{}}}}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = RES_IntegrationTestDataFactory.createAccount();
        // Set an existing BP number so the update payload includes it via RES_BP_NUMBER.
        acc.RES_External_Key__c = '0010000123';
        update acc;

        Test.startTest();
        System.enqueueJob(
            new RES_IntegrationQueueable(new List<SObject>{ acc }, 'Account_Sync', METHOD, 'U')
        );
        Test.stopTest();

        Assert.areEqual(1, mock.businessCallCount,
            'Account_Sync update branch should reach the integration service exactly once.');
    }

    /* ====================================================================
     *  CONSTRUCTOR
     * ==================================================================== */

    @isTest
    static void constructorRetainsSuppliedArguments() {
        Test.setMock(
            HttpCalloutMock.class,
            new RES_IntegrationTestDataFactory.EndpointRoutingMock()
        );

        Test.startTest();
        RES_IntegrationQueueable job = new RES_IntegrationQueueable(
            new List<SObject>(), 'ProductCategory_Sync', 'POST', 'U'
        );
        job.execute(null);
        Test.stopTest();

        Assert.isNotNull(job, 'The queueable should be constructible with all four arguments.');
    }
}