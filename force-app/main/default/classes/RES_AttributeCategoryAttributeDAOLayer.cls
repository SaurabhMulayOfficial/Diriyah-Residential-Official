/*
 * Class Name  : RES_AttributeCategoryAttributeDAOLayer
 * Description : DAO layer for AttributeCategoryAttribute object.
 */
public without sharing class RES_AttributeCategoryAttributeDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'AttributeCategoryAttribute';
    }

    public Integer getCategoryAttributeCount(Id catId, Id attrId) {
        if (catId == null || attrId == null) return 0;
        Map<String, Object> bindVars = new Map<String, Object>{ 'catId' => catId, 'attrId' => attrId };
        String soql = 'SELECT Id FROM AttributeCategoryAttribute WHERE AttributeCategoryId = :catId AND AttributeDefinitionId = :attrId';
        return executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE).size();
    }
}