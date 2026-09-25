/*
 * Class Name  : RES_ContractItemPriceDAOLayer
 * Description : DAO layer for ContractItemPrice object.
 */
public without sharing class RES_ContractItemPriceDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ContractItemPrice';
    }

    public List<ContractItemPrice> getCIPByContractIds(Set<Id> contractIds) {
        if (contractIds == null || contractIds.isEmpty()) {
            return new List<ContractItemPrice>();
        }

        Set<String> cipTypes = new Set<String>{ 'Payment Plan', 'Unit' };

        Map<String, Object> bindVars = new Map<String, Object>{
            'contractIds' => contractIds,
            'cipTypes' => cipTypes
        };

        String soql =
            'SELECT Id, Price, RES_CIP_Type__c, ContractId, ItemId, RES_Product__r.RES_Product_External_ID__c ' +
            'FROM ContractItemPrice ' +
            'WHERE ContractId IN :contractIds ' +
            'AND RES_CIP_Type__c IN :cipTypes ' +
            'AND ItemId != null ' +
            'AND RES_Product__r.RES_Product_External_ID__c != null';

        return (List<ContractItemPrice>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}
