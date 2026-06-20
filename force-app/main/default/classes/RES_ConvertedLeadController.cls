/**
 * Class Name:  RES_ConvertedLeadController
 * Description: Controller Class used to show the tab view of Converted Leads based on
 *              profiles and roles.
 */
public with sharing class RES_ConvertedLeadController {

    @AuraEnabled(cacheable=true)
    public static RES_ConvertedLeadService.ConvertedLeadResponse getConvertedLeads() {
        return RES_ConvertedLeadService.getConvertedLeads();
    }
}