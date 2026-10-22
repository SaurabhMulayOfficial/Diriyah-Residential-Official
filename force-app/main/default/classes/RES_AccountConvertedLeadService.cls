/**
 * Class Name:  RES_AccountConvertedLeadService
 * Description: Service Class used to show the related list of Converted Leads in Account
 *              and Person Account records.
 */
public without sharing class RES_AccountConvertedLeadService {

    public class ConvertedLeadResponse {
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Boolean isPersonAccount;
        @AuraEnabled public List<ConvertedLeadRow> leads;
    }

    public class ConvertedLeadRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String company;
        @AuraEnabled public String email;
        @AuraEnabled public String mobilePhone;
        @AuraEnabled public String ratingLabel;
        @AuraEnabled public Datetime convertedDate;
    }

    @TestVisible private static List<Lead> testConvertedLeads;

    public static ConvertedLeadResponse getConvertedLeadsByAccountId(Id accountId) {
        ConvertedLeadResponse response = new ConvertedLeadResponse();
        response.leads = new List<ConvertedLeadRow>();
        response.totalCount = 0;
        response.isPersonAccount = false;

        if (accountId == null) {
            return response;
        }

        Account accountRecord = getAccountDetails(accountId);
        response.isPersonAccount =
            accountRecord != null && accountRecord.IsPersonAccount;

        List<Lead> convertedLeads =
            getConvertedLeadSourceRecords(accountId);

        response.leads = buildConvertedLeadRows(convertedLeads);
        response.totalCount = response.leads.size();

        return response;
    }

    private static List<Lead> getConvertedLeadSourceRecords(Id accountId) {
        if (
            Test.isRunningTest() &&
            testConvertedLeads != null
        ) {
            return testConvertedLeads;
        }

        return new RES_LeadDAOLayer().getConvertedLeadsByAccountId(accountId);
    }

    private static Account getAccountDetails(Id accountId) {
        List<Account> accounts = [
            SELECT Id, IsPersonAccount
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        if (accounts.isEmpty()) {
            return null;
        }

        return accounts[0];
    }

    private static List<ConvertedLeadRow> buildConvertedLeadRows(List<Lead> leads) {
        Map<String, String> ratingLabelMap =
            getPicklistValueLabelMap(Lead.Rating);

        List<ConvertedLeadRow> rows = new List<ConvertedLeadRow>();

        if (leads == null || leads.isEmpty()) {
            return rows;
        }

        for (Lead ld : leads) {
            ConvertedLeadRow row = new ConvertedLeadRow();
            row.id = ld.Id;
            row.name = ld.Name;
            row.company = ld.Company;
            row.email = ld.Email;
            row.mobilePhone = ld.MobilePhone;
            row.ratingLabel = ratingLabelMap.containsKey(ld.Rating)
                ? ratingLabelMap.get(ld.Rating)
                : ld.Rating;
            row.convertedDate = ld.ConvertedDate;

            rows.add(row);
        }

        return rows;
    }

    private static Map<String, String> getPicklistValueLabelMap(
        Schema.SObjectField fieldToken
    ) {
        Map<String, String> valueLabelMap = new Map<String, String>();

        for (
            Schema.PicklistEntry entry :
            fieldToken.getDescribe().getPicklistValues()
        ) {
            valueLabelMap.put(entry.getValue(), entry.getLabel());
        }

        return valueLabelMap;
    }
    
    public static String getAccountName(Id accountId) {
        Account accountRecord =
            new RES_LeadDAOLayer().getAccountNameById(accountId);

        return accountRecord != null ? accountRecord.Name : '';
    }
}