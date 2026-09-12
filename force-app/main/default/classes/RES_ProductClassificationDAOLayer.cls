/*
 * Class Name  : RES_ProductClassificationDAOLayer
 * Description : DAO layer for ProductClassification object.
 */
public without sharing class RES_ProductClassificationDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'ProductClassification';
    }

    public List<ProductClassification> getClassificationByName(String name) {
        if (String.isBlank(name)) return new List<ProductClassification>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'name' => name };
        String soql = 'SELECT Id FROM ProductClassification WHERE Name = :name LIMIT 1';
        return (List<ProductClassification>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}