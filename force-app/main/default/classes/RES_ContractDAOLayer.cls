/**
 * Class Name   : RES_ContractDAOLayer
 * Description  : Data Access Object (DAO) layer for the Contract object.
 *                Provides standardized methods for querying and retrieving
 *                Contract records within the application.
 *
 * Framework Rule:
 *      - All DAO layers must extend RES_BaseDAOLayer.
 *      - Each implementation must override getSObjectName()
 *        to specify the associated SObject.
 */
public with sharing class RES_ContractDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'Contract';
    }

    /**
     * Get contracts by opportunity IDs
     * @param opportunityIds Set of opportunity IDs
     * @return List of Contract records
     */
    public List<Contract> getContractsByOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return new List<Contract>();
        }
        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('opportunityIds', opportunityIds);

        String soql = 'SELECT Id, Status, SourceOpportunityId ' +
                      'FROM Contract ' +
                      'WHERE SourceOpportunityId IN :opportunityIds';
        return (List<Contract>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}