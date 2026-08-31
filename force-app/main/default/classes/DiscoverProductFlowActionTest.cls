@IsTest
private class DiscoverProductFlowActionTest {

    @IsTest
    static void testGenerateAdditionalContextData() {
        // Create mock Quote record to get a valid Record ID format
        Account testAcc = new Account(Name = 'Test Account');
        insert testAcc;

        Opportunity testOpp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30),
            AccountId = testAcc.Id
        );
        insert testOpp;

        Quote testQuote = new Quote(
            Name = 'Test Quote',
            OpportunityId = testOpp.Id
        );
        insert testQuote;

        // Prepare FlowInput list
        DiscoverProductFlowAction.FlowInput input = new DiscoverProductFlowAction.FlowInput();
        input.objectApiName = 'Quote';
        input.recordId = testQuote.Id;

        List<DiscoverProductFlowAction.FlowInput> inputList = new List<DiscoverProductFlowAction.FlowInput>{ input };

        // Execute Invocable Method
        Test.startTest();
        List<DiscoverProductFlowAction.FlowOutput> outputList = DiscoverProductFlowAction.generateAdditionalContextData(inputList);
        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, outputList, 'Output list should not be null.');
        System.assertEquals(1, outputList.size(), 'Output list should contain exactly 1 element.');
        
        DiscoverProductFlowAction.FlowOutput result = outputList[0];
        System.assertNotEquals(null, result.additionalContextData, 'additionalContextData should not be null.');
        System.assertEquals(1, result.additionalContextData.size(), 'additionalContextData should contain 1 ContextDataInput item.');
        
        runtime_industries_cpq.ContextDataInput contextData = result.additionalContextData[0];
        System.assertEquals('Quote', contextData.nodeName, 'Node name should match Quote.');
        System.assertEquals(testQuote.Id, contextData.nodeData.get('id'), 'Node data ID should match test Quote ID.');
    }
}