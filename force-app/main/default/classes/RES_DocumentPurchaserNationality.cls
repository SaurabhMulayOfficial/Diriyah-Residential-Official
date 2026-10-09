/**
* @ Class Name     	: RES_DocumentPurchaserNationality
* @ Description    	: Flow entry point (invocable) that stamps the Nationality picklist LABEL into the
                      matching "Document Nationality" text field. Business logic lives in RES_NationalityServices.
                      Used in:
                      - RES_Contract_AfterSave_Populate_CompanySignedDate_Hijri flow (Contract)
                      - RES_Account_AfterSave_Populate_Document_Nationality flow (Person Account)
                      - RES_Contact_AfterSave_Populate_Document_Nationality flow (Contact)
* @ Author			: Nikhil Takawale
*/

public with sharing class RES_DocumentPurchaserNationality {
    @InvocableMethod(label = 'Populate Document Purchaser Nationality On Contract')
    public static void validateOpportunity(List<Input> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }
        Set<Id> contractIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (Input inputObj : inputs) {
            if (inputObj.contractRecord != null && inputObj.contractRecord.Id != null) {
                contractIds.add(inputObj.contractRecord.Id);
            }
            if (inputObj.accountRecord != null && inputObj.accountRecord.Id != null) {
                accountIds.add(inputObj.accountRecord.Id);
            }
            if (inputObj.contactRecord != null && inputObj.contactRecord.Id != null) {
                contactIds.add(inputObj.contactRecord.Id);
            }
        }
        RES_NationalityServices.populateContractDocumentNationality(contractIds);
        RES_NationalityServices.populatePersonAccountDocumentNationality(accountIds);
        RES_NationalityServices.populateContactDocumentNationality(contactIds);
    }

    public class Input {
        @InvocableVariable public Contract contractRecord;
        @InvocableVariable public Account accountRecord;
        @InvocableVariable public Contact contactRecord;
    }
}
