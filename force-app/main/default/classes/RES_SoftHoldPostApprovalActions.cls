public with sharing class RES_SoftHoldPostApprovalActions {
    public RES_SoftHoldPostApprovalActions() {}

    public class input{
        @InvocableVariable(required = true)
        public Quote quote;

        @InvocableVariable(required = true)
        public String action;
    }


    @invocableMethod(label='Soft Hold Post Approval Actions' description='Soft Hold Post Approval Actions')

    public static void executeSoftHoldPostApprovalActions(List<input> inputs){
        Set<Id> quoteIds = new Set<Id>();
        for(input inputObj : inputs){
            quoteIds.add(inputObj.quote.Id);
        }
        
        List<QuoteLineItem> quoteLineItems = new RES_QuoteLineItemDAO().getQuoteLineItemsByQuoteIds(quoteIds);
        List<BusinessHours> bhr = new RES_BusinessHoursDAOLayer().getDefaultBusinessHours();

        Map<Id, QuoteLineItem> productToQuoteMap = new Map<Id, QuoteLineItem>();

        for(QuoteLineItem quoteLineItem : quoteLineItems){
            productToQuoteMap.put(quoteLineItem.QuoteId, quoteLineItem);
        }

        List<Product2> productsToUpdate = new List<Product2>();

        for(input inputObj : inputs){
            if(inputObj.action == 'Approve'){
                QuoteLineItem qli = productToQuoteMap.get(inputObj.quote.Id);
                Integer extensionHours = Integer.valueOf(inputObj.quote.RES_Extend_Soft_Hold_By_Hours__c);
                if(qli != null){
                    DateTime softHoldExtensionDate = BusinessHours.add(bhr[0].Id, qli.Product2.RES_Soft_Hold_Until__c, extensionHours * 60 * 60 * 1000);

                    if(softHoldExtensionDate != null && softHoldExtensionDate > DateTime.Now()){
                        Product2 p = new Product2();
                        p.Id = qli.Product2Id;
                        p.RES_Soft_Hold_Start__c = SYSTEM.now();
                        p.RES_Soft_Hold_Until__c = softHoldExtensionDate;
                        p.RES_Is_In_Soft_Hold_Extension__c = false;
                        p.RES_Unit_Status__c = 'Soft Hold';
                        productsToUpdate.add(p);
                    }
                    else{
                        Product2 p = new Product2();
                        p.Id = qli.Product2Id;
                        p.RES_Is_In_Soft_Hold_Extension__c = false;
                        p.RES_Unit_Status__c = 'Available';
                        productsToUpdate.add(p);
                    }
                }
            }
            else if(inputObj.action == 'Reject'){
                QuoteLineItem qli = productToQuoteMap.get(inputObj.quote.Id);
                if(qli != null){
                    Product2 p = new Product2();
                    p.Id = qli.Product2Id;
                    p.RES_Is_In_Soft_Hold_Extension__c = false;
                    if(qli.Product2.RES_Soft_Hold_Until__c != null && qli.Product2.RES_Soft_Hold_Until__c < DateTime.now()){
                        p.RES_Unit_Status__c = 'Available';
                    }
                    productsToUpdate.add(p);
                }
            }
        }

        try{
            if(!productsToUpdate.isEmpty()){
                Database.update(productsToUpdate, false, AccessLevel.SYSTEM_MODE);
            }
        }
        catch(DmlException e){
            System.debug('Error occurred while updating products: ' + e.getMessage());
        }
    }
}