/*
 * Class Name  : RES_Pricebook2DAOLayer
 * Description : DAO layer for Pricebook2 object.
 */
public without sharing class RES_Pricebook2DAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'Pricebook2';
    }

    public List<Pricebook2> getStandardPricebook() {
        String soql = 'SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1';
        return (List<Pricebook2>) executeQuery(soql, 'getStandardPricebook', true, null, AccessLevel.SYSTEM_MODE);
    }

    public List<Pricebook2> getPricebookByName(String bookName) {
        if (String.isBlank(bookName)) return new List<Pricebook2>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'bookName' => bookName };
        String soql = 'SELECT Id, IsActive FROM Pricebook2 WHERE Name = :bookName AND IsStandard = false LIMIT 1';
        return (List<Pricebook2>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }
}