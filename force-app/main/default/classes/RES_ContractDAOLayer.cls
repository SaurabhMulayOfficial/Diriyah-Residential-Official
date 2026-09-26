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

    public List<Contract> getContractsByIds(Set<Id> contractIds) {
        if (contractIds == null || contractIds.isEmpty()) {
            return new List<Contract>();
        }

        Map<String, Object> bindVars = new Map<String, Object>{
            'contractIds' => contractIds
        };

        String soql =
            'SELECT Id, OwnerId, StartDate, Status, RES_Company_Code__c, RES_Approval_Status__c, EndDate, RES_External_ID__c, ContractNumber, Owner.Name, CompanySignedDate, RES_Last_Sync_DateTime__c, ' +
            '       RES_Contract_Type__c, TerminationDateTime, TerminationReason, TerminationType, RES_First_Residential_Buyer__c, DIR_Old_Contract__c, RES_S4_Contract_Id__c, RES_Cancellation_Reason__c, ' +
            '       Account.RES_BP_Role__c ' +
            'FROM Contract ' +
            'WHERE Id IN :contractIds';

        return (List<Contract>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}