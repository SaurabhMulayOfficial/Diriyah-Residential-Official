public with sharing class RES_ApprovalWorkItemManagement {

    public static void processWorkItems(
        List<RES_WorkItemFlowInput> inputs
    ) {
        try {
            Map<String, Object> flowInputs = new Map<String, Object>{
                'WorkItemFlowInput' => inputs
            };

            Flow.Interview flowInterview =
                Flow.Interview.createInterview(
                    'RES_Apex_Invocable_Flow_Review_Approval_Work_Items',
                    flowInputs
                );

            flowInterview.start();

        } catch (Exception e) {
            System.debug(
                'Exception Invoking "RES_Apex_Invocable_Flow_Review_Approval_Work_Items" Flow: '
                + e.getMessage()
            );
        }
    }
}