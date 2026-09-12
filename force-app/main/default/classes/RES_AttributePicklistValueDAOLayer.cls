/*
 * Class Name  : RES_AttributePicklistValueDAOLayer
 * Description : DAO layer for AttributePicklistValue object.
 */
public without sharing class RES_AttributePicklistValueDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'AttributePicklistValue';
    }

    public List<AttributePicklistValue> getValuesByPicklistId(Id picklistId) {
        if (picklistId == null) return new List<AttributePicklistValue>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'picklistId' => picklistId };
        String soql = 'SELECT Value FROM AttributePicklistValue WHERE PicklistId = :picklistId';
        return (List<AttributePicklistValue>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}