/**
 * Class Name:  RES_AccountConvertedLeadController
 * Description: Controller Class used to show the related list of Converted Leads in Account
 *              and Person Account records.
 */
public with sharing class RES_AccountConvertedLeadController {

    @AuraEnabled(cacheable=true)
    public static RES_AccountConvertedLeadService.ConvertedLeadResponse getConvertedLeadsByAccountId(
        Id accountId
    ) {
        return RES_AccountConvertedLeadService.getConvertedLeadsByAccountId(accountId);
    }

    @AuraEnabled(cacheable=true)
    public static String getAccountName(Id accountId) {
        return RES_AccountConvertedLeadService.getAccountName(accountId);
    }
}