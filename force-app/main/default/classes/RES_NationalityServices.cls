/**
 * @description Service layer that resolves the picklist LABEL of a Nationality field into its
 *              "Document Nationality" text field, so document generation prints the label
 *              instead of the API value. Covers Contract (PAR Nationality), Person Account
 *              and Contact. Records are re-queried through the DAO layers so the values
 *              used are always the latest saved ones.
 *
 * @author Syed Ashraf
 */
public with sharing class RES_NationalityServices {
    private static final Integer DOCUMENT_NATIONALITY_MAX_LENGTH = 255;

    public static void populateContractDocumentNationality(Set<Id> contractIds) {
        Map<Id, Contract> contracts = new RES_ContractDAOLayer().getContractsNationalityByIds(contractIds);
        if (contracts.isEmpty()) {
            return;
        }
        Map<String, String> labelMap = getPicklistValuesMap(Contract.RES_PAR_Nationality__c.getDescribe());
        List<Contract> toUpdate = new List<Contract>();
        for (Contract con : contracts.values()) {
            // Existing behaviour: a blank/unknown nationality leaves the document field untouched
            String label = resolveLabel(labelMap, con.RES_PAR_Nationality__c);
            if (label != null && label != con.RES_Document_PAR_Nationality__c) {
                toUpdate.add(new Contract(Id = con.Id, RES_Document_PAR_Nationality__c = label));
            }
        }
        updateRecords(toUpdate);
    }

    public static void populatePersonAccountDocumentNationality(Set<Id> accountIds) {
        Map<Id, Account> accounts = new RES_AccountDAOLayer().getPersonAccountsNationalityByIds(accountIds);
        if (accounts.isEmpty()) {
            return;
        }
        Map<String, String> labelMap = getPicklistValuesMap(Account.RES_Nationality__pc.getDescribe());
        List<Account> toUpdate = new List<Account>();
        for (Account acc : accounts.values()) {
            String label = resolveLabel(labelMap, acc.RES_Nationality__pc);
            if (label != acc.RES_Document_Nationality__pc) {
                toUpdate.add(new Account(Id = acc.Id, RES_Document_Nationality__pc = label));
            }
        }
        updateRecords(toUpdate);
    }

    public static void populateContactDocumentNationality(Set<Id> contactIds) {
        Map<Id, Contact> contacts = new RES_ContactDAOLayer().getContactsNationalityByIds(contactIds);
        if (contacts.isEmpty()) {
            return;
        }
        Map<String, String> labelMap = getPicklistValuesMap(Contact.RES_Nationality__c.getDescribe());
        List<Contact> toUpdate = new List<Contact>();
        for (Contact con : contacts.values()) {
            String label = resolveLabel(labelMap, con.RES_Nationality__c);
            if (label != con.RES_Document_Nationality__c) {
                toUpdate.add(new Contact(Id = con.Id, RES_Document_Nationality__c = label));
            }
        }
        updateRecords(toUpdate);
    }

    // Generic: builds API value -> label map (active entries only) for any picklist field
    public static Map<String, String> getPicklistValuesMap(Schema.DescribeFieldResult fieldDescribe) {
        Map<String, String> picklistValuesMap = new Map<String, String>();
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive() && !picklistValuesMap.containsKey(entry.getValue())) {
                picklistValuesMap.put(entry.getValue(), entry.getLabel());
            }
        }
        return picklistValuesMap;
    }

    // Label for the value (cut to the field length), or null when the value is blank or unknown
    @TestVisible
    private static String resolveLabel(Map<String, String> picklistValuesMap, String value) {
        String label = String.isBlank(value) ? null : picklistValuesMap.get(value);
        return label == null ? null : label.left(DOCUMENT_NATIONALITY_MAX_LENGTH);
    }

    private static void updateRecords(List<SObject> records) {
        if (!records.isEmpty()) {
            Database.update(records, false, AccessLevel.SYSTEM_MODE);
        }
    }
}
