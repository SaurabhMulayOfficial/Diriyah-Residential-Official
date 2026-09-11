/*
 * Class Name  : RES_AttributeDefinitionDAOLayer
 * Description : DAO layer for AttributeDefinition object.
 */
public without sharing class RES_AttributeDefinitionDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'AttributeDefinition';
    }

    public List<AttributeDefinition> getAttributeDefinitionsByNames(Set<String> names) {
        if (names == null || names.isEmpty()) return new List<AttributeDefinition>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'names' => names };
        String soql = 'SELECT Id, Name FROM AttributeDefinition WHERE Name IN :names';
        return (List<AttributeDefinition>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public List<AttributeDefinition> getAttributeDefinitionsByIds(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) return new List<AttributeDefinition>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'ids' => ids };
        String soql = 'SELECT Id, Name FROM AttributeDefinition WHERE Id IN :ids';
        return (List<AttributeDefinition>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public List<AttributeDefinition> getAttributeDefinitionByName(String name) {
        if (String.isBlank(name)) return new List<AttributeDefinition>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'name' => name };
        String soql = 'SELECT Id, PicklistId FROM AttributeDefinition WHERE Name = :name LIMIT 1';
        return (List<AttributeDefinition>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}