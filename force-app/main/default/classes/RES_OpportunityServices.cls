public with sharing class RES_OpportunityServices {
    public RES_OpportunityServices() {}

    
    public static void applySoftHoldOnProducts(List<Opportunity> opportunityList, Map<Id, Opportunity> oldMap){
        List<Opportunity> eligibleOpportunities = new List<Opportunity>();

        for(Opportunity opp: opportunityList){
            if(opp.StageName != oldMap.get(opp.Id).StageName && opp.StageName == 'Reservation'){
                eligibleOpportunities.add(opp);
            }
        }

        if(eligibleOpportunities.size() > 0){
            RES_ProductOrchestrator.applySoftHold(eligibleOpportunities);
        }
    }
}   