public with sharing class POC_ProductRecommendationController {

    @AuraEnabled
    public static Map<String, Object> getComponentData(Id recordId, String objectApiName) {
        Map<String, Object> result = new Map<String, Object>();
        String savedIds = '';
        
        // --- LEAD LOGIC ---
        if (objectApiName == 'Lead') {
            Lead l = [SELECT Id, POC_Recommended_Products__c, RES_Area_Of_Interest__c, RES_Interest_Type__c, RES_Project_of_Interest__c 
                      FROM Lead WHERE Id = :recordId LIMIT 1];
            savedIds = l.POC_Recommended_Products__c;
            
            // Evaluate Business Rules based on the provided matrix
            List<String> productNames = new List<String>();
            
            // Rule 1: Luxury Armani Villa
            if(l.RES_Area_Of_Interest__c == 'RESIDENTIAL_SALES' && l.RES_Interest_Type__c == 'Armani_Brochure' && l.RES_Project_of_Interest__c == '6 Bedroom Villas') {
                productNames.add('Armani Ultra-Luxury 6-Bedroom Villa Package');
            }
            // Rule 2: Baccarat Investment
            if(l.RES_Area_Of_Interest__c == 'INVESTMENT' && l.RES_Interest_Type__c == 'BR_BACCARAT_BROCHURE' && l.RES_Project_of_Interest__c == 'DiriyahSquare') {
                productNames.add('Baccarat Residences Premium Portfolio');
            }
            // Rule 3: Commercial B2B Retail
            if(l.RES_Area_Of_Interest__c == 'RETAIL_LEASING' && l.RES_Interest_Type__c == 'B2B_Retail_Leasing' && l.RES_Project_of_Interest__c == 'DiriyahSquare') {
                productNames.add('Diriyah Square Premium Retail Space Allocation');
            }
            
            // Fetch the actual Product records if any rules matched
            if(!productNames.isEmpty()) {
                List<Product2> recommendedProds = [SELECT Id, Name, Description, ProductCode FROM Product2 WHERE Name IN :productNames AND IsActive = true];
                result.put('recommendedProducts', recommendedProds);
                result.put('hasRecommendations', !recommendedProds.isEmpty());
            } else {
                result.put('hasRecommendations', false);
            }
        } 
        // --- OPPORTUNITY LOGIC ---
        else if (objectApiName == 'Opportunity') {
            Opportunity opp = [SELECT Id, POC_Recommended_Products__c FROM Opportunity WHERE Id = :recordId LIMIT 1];
            savedIds = opp.POC_Recommended_Products__c;
            result.put('hasRecommendations', false); // Opps just display saved products
        }
        
        // Fetch the already saved/selected products to display in the standard table
        if (String.isNotBlank(savedIds)) {
            List<String> idList = savedIds.split(',');
            List<Product2> savedProds = [SELECT Id, Name, Description, ProductCode FROM Product2 WHERE Id IN :idList];
            result.put('savedProducts', savedProds);
        }
        
        result.put('savedIds', savedIds);
        return result;
    }

    @AuraEnabled
    public static void saveSelectedProducts(Id recordId, String objectApiName, String selectedIds) {
        if (objectApiName == 'Lead') {
            update new Lead(Id = recordId, POC_Recommended_Products__c = selectedIds);
        } else if (objectApiName == 'Opportunity') {
            update new Opportunity(Id = recordId, POC_Recommended_Products__c = selectedIds);
        }
    }
}