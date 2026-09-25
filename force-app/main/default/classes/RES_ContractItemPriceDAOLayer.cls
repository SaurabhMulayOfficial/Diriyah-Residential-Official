/*
 * Class Name  : RES_ContractItemPriceDAOLayer
 * Description : DAO layer for ContractItemPrice object.
 */
public without sharing class RES_ContractItemPriceDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ContractItemPrice';
    }

     public List<ContractItemPrice> getInstallmentsByContractIds(Set<Id> contractIds) {
        String soql = 'SELECT Id, Name, Price, ContractId, RES_Product__r.Name ' +
                      'FROM ContractItemPrice ' +
                      'WHERE ContractId IN :contractIds ' +
                      'AND RES_Installments_Check__c = true';
        Map<String, Object> bindVars = new Map<String, Object>{ 'contractIds' => contractIds };
        return (List<ContractItemPrice>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}