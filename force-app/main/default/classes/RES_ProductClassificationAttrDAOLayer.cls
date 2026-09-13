/*
 * Class Name  : RES_ProductClassificationAttrDAOLayer
 * Description : DAO layer for ProductClassificationAttr object.
 */
public without sharing class RES_ProductClassificationAttrDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ProductClassificationAttr';
    }

    public List<ProductClassificationAttr> getClassAttrsByClassAndAttrs(Id classId, Set<Id> attrIds) {
        if (classId == null || attrIds == null || attrIds.isEmpty()) return new List<ProductClassificationAttr>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'classId' => classId, 'attrIds' => attrIds };
        String soql = 'SELECT Id, AttributeDefinitionId FROM ProductClassificationAttr ' +
                      'WHERE ProductClassificationId = :classId AND AttributeDefinitionId IN :attrIds';
        return (List<ProductClassificationAttr>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}