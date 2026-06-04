/**
 * Class Name   : RES_CountryDialCodeDAOLayer
 * Description  : Data Access Object (DAO) layer for StaticResource.
 *                Provides standardized methods for querying and retrieving
 *                country dial code JSON used for Lead mobile normalization.
 *
 * Framework Rule:
 *      - All DAO layers must extend RES_BaseDAOLayer.
 *      - Each implementation must override getSObjectName()
 *        to specify the associated SObject.
 */
public with sharing class RES_CountryDialCodeDAOLayer extends RES_BaseDAOLayer {

    protected override String getSObjectName() {
        return 'StaticResource';
    }

    /**
     * Returns the SObject API name.
     * @return SObject API name.
     */
    public StaticResource getCountryDialCodeResource() {
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('resourceName', 'RES_AllCountryDialCode');

        String soql =
            'SELECT Body ' +
            'FROM StaticResource ' +
            'WHERE Name = :resourceName ' +
            'LIMIT 1';

        List<SObject> results = executeQuery(
            soql,
            'RES_AllCountryDialCode',
            true,
            bindVars,
            AccessLevel.SYSTEM_MODE
        );

        return results.isEmpty() ? null : (StaticResource) results[0];
    }
}