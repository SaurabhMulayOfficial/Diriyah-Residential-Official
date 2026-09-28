/**
 * @description Shared test utilities for the RES integration test suite.
 *
 *              Provides HTTP callout mocks that route by endpoint (SAP token
 *              vs business callout) and factory methods for ProductCatalog,
 *              ProductCategory and RES_Measurement__c records.
 *
 *              Marked @isTest so it does not count against org code size and
 *              cannot be referenced from production code.
 */
@isTest
public class RES_IntegrationTestDataFactory {

    public static final String TOKEN_ENDPOINT_FRAGMENT = 'SAPToken';
    public static final String MOCK_ACCESS_TOKEN = 'mock-sap-access-token';

    /* ====================================================================
     *  HTTP MOCKS
     * ==================================================================== */

    /**
     * Routes responses by endpoint so a single mock can serve both the SAP
     * token callout and the business callout in the same transaction.
     * Every knob is public so individual tests can reshape behaviour.
     */
    public class EndpointRoutingMock implements HttpCalloutMock {

        // Token leg
        public Integer tokenCallCount = 0;
        public Integer tokenStatusCode = 200;
        public String tokenStatus = 'OK';
        public String tokenBody = '{"access_token":"' + MOCK_ACCESS_TOKEN + '"}';

        // Business leg
        public Integer businessCallCount = 0;
        public Integer businessStatusCode = 200;
        public String businessStatus = 'OK';
        public String businessBody = '{"result":"ok"}';
        public List<HttpRequest> businessRequests = new List<HttpRequest>();

        // Failure switches
        public Boolean throwOnToken = false;
        public Boolean throwOnBusiness = false;

        public HttpResponse respond(HttpRequest req) {
            Boolean isTokenCall =
                req.getEndpoint() != null &&
                req.getEndpoint().containsIgnoreCase(TOKEN_ENDPOINT_FRAGMENT);

            HttpResponse res = new HttpResponse();

            if (isTokenCall) {
                this.tokenCallCount++;
                if (this.throwOnToken) {
                    throw new CalloutException('Simulated token callout failure');
                }
                res.setStatusCode(this.tokenStatusCode);
                res.setStatus(this.tokenStatus);
                res.setBody(this.tokenBody);
                return res;
            }

            this.businessCallCount++;
            this.businessRequests.add(req);
            if (this.throwOnBusiness) {
                throw new CalloutException('Simulated business callout failure');
            }
            res.setStatusCode(this.businessStatusCode);
            res.setStatus(this.businessStatus);
            res.setBody(this.businessBody);
            return res;
        }

        /** Convenience: the body of the last business callout sent. */
        public String lastBusinessBody() {
            return this.businessRequests.isEmpty()
                ? null
                : this.businessRequests[this.businessRequests.size() - 1].getBody();
        }
    }

    /* ====================================================================
     *  TOKEN HELPERS
     * ==================================================================== */

    /**
     * Pre-seeds the cached SAP token so constructing an integration service
     * does not trigger the token callout. Call this in almost every test.
     */
    public static void primeSapToken() {
        RES_SAPTokenProvider.SAP_TOKEN = MOCK_ACCESS_TOKEN;
    }

    /** Clears the cached token so the token callout path is exercised. */
    public static void clearSapToken() {
        RES_SAPTokenProvider.SAP_TOKEN = '';
    }

    /* ====================================================================
     *  RECORD FACTORIES
     * ==================================================================== */

    public static ProductCatalog createCatalog() {
        ProductCatalog catalog = new ProductCatalog(Name = 'RES Test Catalog');
        insert catalog;
        return catalog;
    }

    /**
     * Builds (without inserting) a ProductCategory populated with every field
     * the request wrapper reads.
     */
    public static ProductCategory buildCategory(Id catalogId, String name, String propertyId) {
        return new ProductCategory(
            CatalogId                 = catalogId,
            Name                      = name,
            RES_Company_Code__c       = '1000',
            RES_Business_Entity_Id__c = 'BE-001',
            RES_Property_ID__c        = propertyId,
            RES_Valid_From_Date__c    = Date.newInstance(2026, 1, 1),
            RES_Valid_To_Date__c      = Date.newInstance(2026, 12, 31),
            RES_Profit_Center__c      = 'PC-100',
            RES_Property_Type__c      = 'Land'
        );
    }

    /** Inserts and returns a list of ProductCategory records. */
    public static List<ProductCategory> createCategories(Integer count, Boolean withPropertyId) {
        ProductCatalog catalog = createCatalog();
        List<ProductCategory> categories = new List<ProductCategory>();
        for (Integer i = 0; i < count; i++) {
            categories.add(
                buildCategory(
                    catalog.Id,
                    'Test Category ' + i,
                    withPropertyId ? 'PROP-' + i : null
                )
            );
        }
        insert categories;
        return categories;
    }

    /**
     * Builds (without inserting) a measurement tied to the given category.
     */
    public static RES_Measurement__c buildMeasurement(Id categoryId, String measurementType) {
        return new RES_Measurement__c(
            RES_Category__c           = categoryId,
            RES_Measurement_Type__c   = measurementType,
            RES_Measurement_Amount__c = 125.50,
            RES_Measurement_From__c   = Date.newInstance(2026, 1, 1),
            RES_Measurement_To__c     = Date.newInstance(2026, 6, 30)
        );
    }

    public static List<RES_Measurement__c> createMeasurements(Id categoryId, Integer count) {
        List<RES_Measurement__c> measurements = new List<RES_Measurement__c>();
        for (Integer i = 0; i < count; i++) {
            measurements.add(buildMeasurement(categoryId, 'Z002'));
        }
        insert measurements;
        return measurements;
    }

    /* ====================================================================
     *  METADATA GUARD
     * ==================================================================== */

    /**
     * Returns true when the org has an API configuration for the given
     * request method. Custom metadata cannot be created in a test, so tests
     * that construct the integration service depend on deployed records.
     */
    public static Boolean hasApiConfiguration(String requestMethod) {
        return !new RES_APIConfigurationsDAO()
            .getAPIConfiguration(requestMethod, 'Building_Land_API')
            .isEmpty();
    }

    /** Same guard for the Product Catalog API configuration. */
    public static Boolean hasProductCatalogApiConfiguration(String requestMethod) {
        return !new RES_APIConfigurationsDAO()
            .getAPIConfiguration(requestMethod, 'Product_Catalog_API')
            .isEmpty();
    }

    /**
     * Builds (without inserting) a measurement tied to the given ProductCatalog.
     * RES_Catalog__c is required by hydrateCatalogWithMeasurements.
     */
    public static RES_Measurement__c buildMeasurementForCatalog(Id catalogId, String measurementType) {
        return new RES_Measurement__c(
            RES_Catalog__c            = catalogId,
            RES_Measurement_Type__c   = measurementType,
            RES_Measurement_Amount__c = 250.00,
            RES_Measurement_From__c   = Date.newInstance(2026, 1, 1),
            RES_Measurement_To__c     = Date.newInstance(2026, 12, 31)
        );
    }

    public static List<RES_Measurement__c> createMeasurementsForCatalog(Id catalogId, Integer count) {
        List<RES_Measurement__c> measurements = new List<RES_Measurement__c>();
        for (Integer i = 0; i < count; i++) {
            measurements.add(buildMeasurementForCatalog(catalogId, 'Z002'));
        }
        insert measurements;
        return measurements;
    }
}