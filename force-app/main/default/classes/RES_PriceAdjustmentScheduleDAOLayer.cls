/*
 * Class Name  : RES_PriceAdjustmentScheduleDAOLayer
 * Description : DAO layer for PriceAdjustmentSchedule object.
 */
public without sharing class RES_PriceAdjustmentScheduleDAOLayer extends RES_BaseDAOLayer {
    protected override String getSObjectName() {
        return 'PriceAdjustmentSchedule';
    }

    public List<PriceAdjustmentSchedule> getActiveScheduleByName(String name) {
        if (String.isBlank(name)) return new List<PriceAdjustmentSchedule>();
        Map<String, Object> bindVars = new Map<String, Object>{ 'name' => name };
        String soql = 'SELECT Id FROM PriceAdjustmentSchedule WHERE Name = :name AND IsActive = true LIMIT 1';
        return (List<PriceAdjustmentSchedule>) executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
    }

    public PriceAdjustmentSchedule getScheduleById(Id scheduleId) {
        if (scheduleId == null) return null;
        Map<String, Object> bindVars = new Map<String, Object>{ 'scheduleId' => scheduleId };
        String soql = 'SELECT Id, EffectiveFrom, EffectiveTo FROM PriceAdjustmentSchedule WHERE Id = :scheduleId LIMIT 1';
        List<SObject> results = executeQuery(soql, '', false, bindVars, AccessLevel.SYSTEM_MODE);
        return results.isEmpty() ? null : (PriceAdjustmentSchedule) results[0];
    }
}