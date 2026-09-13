/*
 * Class Name  : RES_AttributeCategoryDAOLayer
 * Description : DAO layer for AttributeCategory object.
 */
public without sharing class RES_AttributeCategoryDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'AttributeCategory';
    }

    public List<AttributeCategory> getCategoryByName(String name) {
        if (String.isBlank(name)) return new List<AttributeCategory>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'name' => name };
        String soql = 'SELECT Id FROM AttributeCategory WHERE Name = :name LIMIT 1';
        return (List<AttributeCategory>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}