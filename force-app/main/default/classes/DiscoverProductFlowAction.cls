public class DiscoverProductFlowAction {
    
    // Define input parameters
    public class FlowInput {
        @InvocableVariable(required=false)
        public String objectApiName;
        
        @InvocableVariable(required=false)
        public String recordId;
    }
    
    // Define output parameters     
    public class FlowOutput {
        @InvocableVariable
        public runtime_industries_cpq.ContextDataInput[] additionalContextData;
    }

    // This method is invoked from a flow
    @InvocableMethod(label='Process Input' description='Creates the Array of ContextDataInput for additional Context Data')
    public static List<FlowOutput> generateAdditionalContextData(List<FlowInput> inputs) {
        String apiName;
        String recId;
        FlowOutput output = new FlowOutput();
        
        // Capture input from the flow
		for(FlowInput input : inputs ){
            apiName = input.objectApiName;
            recId = input.recordId;
        }

        //Populate the ContextDataInput list to store additional context data
      	List<runtime_industries_cpq.ContextDataInput> listContextData = new List<runtime_industries_cpq.ContextDataInput>();
        runtime_industries_cpq.ContextDataInput cd1 = new runtime_industries_cpq.ContextDataInput();
        cd1.nodeName = 'Quote'; //Where Quote is the name of the node in the context definition.
        cd1.nodeData = new Map<String,Object>();
        cd1.nodeData.put('id',recId);       
        listContextData.add(cd1);
        
        // Return the additional Context Data to a flow
        output.additionalContextData = listContextData;
        return new List<FlowOutput>{output};       
    }
}