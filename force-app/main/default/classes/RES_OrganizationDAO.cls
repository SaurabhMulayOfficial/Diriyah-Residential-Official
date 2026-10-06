/**
 * Class Name  : RES_OrganizationDAO
 * Description : DAO layer for the Organization object.
 */
public without sharing class RES_OrganizationDAO extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'Organization';
    }

    /** @description The org's default time zone (TimeZoneSidKey), e.g. Asia/Riyadh. */
    public String getTimeZoneSidKey() {
        List<SObject> rows = executeQuery('SELECT TimeZoneSidKey FROM Organization LIMIT 1', '', false, null, AccessLevel.SYSTEM_MODE);
        return rows.isEmpty() ? null : (String) rows[0].get('TimeZoneSidKey');
    }
}
