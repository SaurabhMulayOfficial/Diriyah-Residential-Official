// ONE-TIME backfill of Opportunity.RES_Lead__c for Leads converted before RES_Lead_AfterUpdate_Stamp_Converted_Opportunity was deployed.
// Source of truth is Lead.ConvertedOpportunityId. Self-contained anonymous Apex - depends on no deployed class. Run ONCE per org:
//   sf apex run -o <alias> -f scripts/apex/backfill_opportunity_lead.apex
// Defaults to DRY RUN (no DML). Set dryRun = false to apply. Safe to re-run: only Opportunities with a null RES_Lead__c are touched.
// If the volume exceeds the 10,000 DML row limit, re-run until candidates = 0 (each run handles the first batchSize).
Boolean dryRun = true;
Integer batchSize = 5000;

Map<Id, Opportunity> toUpdate = new Map<Id, Opportunity>();
for (Lead l : [
    SELECT Id, ConvertedOpportunityId
    FROM Lead
    WHERE IsConverted = true AND ConvertedOpportunityId != NULL AND ConvertedOpportunity.RES_Lead__c = NULL
    LIMIT :batchSize
]) {
    toUpdate.put(l.ConvertedOpportunityId, new Opportunity(Id = l.ConvertedOpportunityId, RES_Lead__c = l.Id));
}

Integer updated = 0;
Integer failed = 0;
if (!dryRun && !toUpdate.isEmpty()) {
    for (Database.SaveResult r : Database.update(toUpdate.values(), false)) {
        if (r.isSuccess()) { updated++; } else { failed++; System.debug(LoggingLevel.ERROR, r.getErrors()); }
    }
}
System.debug('dryRun: ' + dryRun + ', candidates: ' + toUpdate.size() + ', updated: ' + updated + ', failed: ' + failed);
